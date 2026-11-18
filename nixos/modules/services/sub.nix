{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.subscriptionPublisher;
  domain = config.networking.domain;
  proxyPublicTcp = config.services.mihomo.routing.proxyPublicSsh or false;
  sshPorts = lib.unique (
    [
      22
      (config.ports.ssh or 1022)
    ]
    ++ lib.filter (p: p != 80 && p != 443) (
      lib.mapAttrsToList (_: h: h.port) (config.programs.ssh.customHosts or { })
    )
  );
  subscriptionPathToken = config.sops.placeholder."xray/subscription_path_token";

  # 从 server 字段提取主机名标识符（如 "fra0.dora.im" -> "fra0", "fra0" -> "fra0"）
  serverHost = server: lib.head (lib.splitString "." server);

  # 从主机名或 server 字段提取区域标识（如 "tyo0" -> "TYO", "fra0" -> "FRA", "hkg5" -> "HKG"）
  extractRegion =
    server:
    let
      base = serverHost server;
      matched = builtins.match "^([a-zA-Z]+)[0-9].*" base;
    in
    lib.toUpper (if matched != null then builtins.head matched else base);

  getNodeRegions =
    node: if node.regions != [ ] then node.regions else [ (extractRegion node.server) ];

  # 动态提取并去重的 regionNames 列表（无需手动硬编码）
  regionNames = lib.unique (lib.concatMap getNodeRegions cfg.nodes);

  publicServer = server: if lib.hasInfix "." server then server else "${server}.${domain}";

  # 公网直连节点（VLESS Reality 或 Shadowsocks）
  mkPublicNode =
    node:
    let
      server = publicServer node.server;
      nodeType = node.type or "vless";
    in
    if nodeType == "ss" then
      {
        inherit (node) name port;
        type = "ss";
        inherit server;
        cipher = node.cipher or "2022-blake3-aes-128-gcm";
        password = if node.password != null then node.password else config.sops.placeholder."xray/uuid";
        udp = true;
      }
    else
      {
        inherit (node) name port;
        type = "vless";
        inherit server;
        uuid = config.sops.placeholder."xray/uuid";
        network = cfg.transport;
        tls = true;
        udp = true;
        servername = cfg.serverName;
        reality-opts = {
          public-key = config.sops.placeholder."xray/public_key";
          short-id = config.sops.placeholder."xray/short_id";
          support-x25519mlkem768 = true;
        };
        client-fingerprint = "chrome";
      }
      // lib.optionalAttrs (cfg.transport == "tcp") {
        flow = "xtls-rprx-vision";
      }
      // lib.optionalAttrs (cfg.transport == "xhttp") {
        xhttp-opts = {
          path = cfg.xhttpPath;
          host = cfg.serverName;
          mode = cfg.xhttpMode;
          x-padding-bytes = cfg.xhttpExtra.xPaddingBytes;
          x-padding-obfs-mode = cfg.xhttpExtra.xPaddingObfsMode;
          x-padding-placement = cfg.xhttpExtra.xPaddingPlacement;
          x-padding-header = cfg.xhttpExtra.xPaddingHeader;
          x-padding-method = cfg.xhttpExtra.xPaddingMethod;
          reuse-settings = {
            max-connections = cfg.xhttpXmux.maxConnections;
            h-max-request-times = cfg.xhttpXmux.hMaxRequestTimes;
            h-max-reusable-secs = cfg.xhttpXmux.hMaxReusableSecs;
            h-keep-alive-period = cfg.xhttpXmux.hKeepAlivePeriod;
          };
          # Absorbs burst loss on high-RTT links. Effective for packet-up;
          # ignored by stream-one, which has no separate upload POSTs.
          uplink-chunk-size = cfg.xhttpUplinkChunkSize;
          sc-max-each-post-bytes = cfg.xhttpScMaxEachPostBytes;
          sc-min-posts-interval-ms = cfg.xhttpScMinPostsIntervalMs;
        };
      };

  publicNodes = map mkPublicNode cfg.nodes;

  publicNodeNames = map (n: n.name) publicNodes;

  # 区域策略组：针对每个 Region 生成 <REGION>
  mkPublicRegionGroup = region: {
    name = region;
    type = "url-test";
    url = cfg.healthCheckUrl;
    interval = 300;
    tolerance = 20;
    proxies = map (node: node.name) (
      lib.filter (node: builtins.elem region (getNodeRegions node)) cfg.nodes
    );
  };

  publicRegionGroups = lib.filter (g: g.proxies != [ ]) (map mkPublicRegionGroup regionNames);

  allRegionGroupNames = map (g: g.name) publicRegionGroups;

  # 通用成员解析函数：
  # nodes: 手动指定的节点名列表（按用户传入顺序排在前面）
  # groups: 手动指定的群组名列表（支持引用策略组名如 UNLOCK、地区名如 JP，以及 "!HK" 排除语法）
  # expandGroups: 是否将群组展开为其所包含的底层节点
  resolveMembers =
    {
      nodes ? [ ],
      groups ? [ ],
      expandGroups ? false,
    }:
    let
      resolvedGroupNames = lib.concatMap (
        g:
        if lib.hasPrefix "!" g then
          let
            excluded = lib.removePrefix "!" g;
          in
          lib.filter (r: r != excluded) allRegionGroupNames
        else
          [ g ]
      ) groups;

      expandedNodeNames =
        if expandGroups then
          lib.concatMap (
            g:
            if g == "ALL" then
              publicNodeNames
            else if g == "PUBLIC-ONLY" then
              publicNodeNames
            else if builtins.elem g regionNames then
              map (n: n.name) (lib.filter (n: builtins.elem g (getNodeRegions n)) cfg.nodes)
            else
              [ g ]
          ) resolvedGroupNames
        else
          resolvedGroupNames;
    in
    lib.unique (nodes ++ expandedNodeNames);

  mkUserGroup =
    g:
    let
      resolvedProxies =
        if g.proxies != [ ] then
          g.proxies
        else
          resolveMembers {
            inherit (g) nodes groups expandGroups;
          };
    in
    if resolvedProxies == [ ] then
      null
    else
      {
        inherit (g)
          name
          type
          url
          interval
          tolerance
          ;
        proxies = resolvedProxies;
      };

  userGroupDefs = lib.filter (g: g != null) (map mkUserGroup cfg.groups);
  userGroupRules = lib.concatMap (g: g.rules) cfg.groups;

  # 汇总策略组
  summaryGroups = [
    {
      name = "ALL";
      type = "url-test";
      url = cfg.healthCheckUrl;
      interval = 300;
      tolerance = 20;
      proxies = publicNodeNames;
    }
  ];

  mihomoConfig = {
    mixed-port = 7890;
    mode = "Rule";
    log-level = "info";
    allow-lan = true;
    bind-address = "0.0.0.0";
    ipv6 = true;
    udp = true;
    unified-delay = true;
    tcp-concurrent = true;
    find-process-mode = "always";
    external-controller = "0.0.0.0:9090";
    external-ui = "./dashboard";
    redir-port = 9797;
    tproxy-port = 9898;
    secret = "";

    # Linux 策略路由防火墙标记 (fwmark)：
    # 所有 Mihomo 出站 socket（包括 DIRECT 直连及节点健康检查）均携带 fwmark 1，
    # 结合 route_output 打标与 priority 8995 防回环绝缘墙，确保直连流量直接查 main 表，
    # 彻底越过 TUN 的 table 2022，根除本地 DIRECT 流量环路回流死锁。
    # routing-mark = 1;

    proxies = publicNodes;

    proxy-groups = [
      # GLOBAL 全局组：用于 Mihomo 切换到全局模式（Global）时的统一出口，默认遵循 PROXY
      {
        name = "GLOBAL";
        type = "select";
        proxies = [
          "PROXY"
          "ALL"
        ]
        ++ (map (g: g.name) userGroupDefs)
        ++ allRegionGroupNames
        ++ [ "DIRECT" ];
      }

      # PROXY 规则代理主选择组：支持全部节点、自定义组与各地区组
      {
        name = "PROXY";
        type = "select";
        proxies = [
          "ALL"
        ]
        ++ (map (g: g.name) userGroupDefs)
        ++ allRegionGroupNames;
      }
    ]
    ++ userGroupDefs
    ++ summaryGroups
    ++ publicRegionGroups;

    rules = [
      # 绕过本机的 microsocks / sing-box 代理，防止循环或被 mihomo 捕获导致 IP 变成节点 IP
      "UID,999,DIRECT"
      "PROCESS-NAME,microsocks,DIRECT"
      "PROCESS-NAME,sing-box,DIRECT"

      # 防环路与直连放行：IPsec/IKE (charon) 与 BIRD 路由守护进程
      "PROCESS-NAME,charon,DIRECT"
      "PROCESS-NAME,charon-systemd,DIRECT"
      "PROCESS-NAME,bird,DIRECT"
    ]
    # 放行 IPsec 协商与 Babel IGP (6696) 端口
    ++ (map (p: "DST-PORT,${toString p},DIRECT") (
      config.services.dn42.allClusterTunnelPorts or [
        500
        4500
      ]
    ))
    ++ [
      "DST-PORT,6696,DIRECT"
    ]
    ++ lib.optionals (!proxyPublicTcp) [
      "DST-PORT,22,DIRECT"
      "DST-PORT,1022,DIRECT"
    ]
    ++ [
      # 私网内网段直连，交由内核路由表处理，绝不进代理环路
      "IP-CIDR,172.20.0.0/14,DIRECT,no-resolve"
      "IP-CIDR,172.31.0.0/16,DIRECT,no-resolve"
      "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve"
      "IP-CIDR,fd00::/8,DIRECT,no-resolve"
    ]
    ++ lib.optionals proxyPublicTcp (
      [
        # Resolve private destinations before the public SSH/domain overrides.
        "GEOSITE,private,DIRECT"
        "GEOIP,private,DIRECT"
        "IP-CIDR,100.64.0.0/10,DIRECT,no-resolve"
        "IP-CIDR,fc00::/7,DIRECT,no-resolve"
        "DOMAIN-SUFFIX,ts,DIRECT"
        "DOMAIN-SUFFIX,et,DIRECT"
      ]
      # Keep domestic SSH direct (including non-standard custom ports).
      ++ map (p: "AND,((NETWORK,TCP),(DST-PORT,${toString p}),(GEOIP,CN)),DIRECT") sshPorts
      ++ map (p: "AND,((NETWORK,TCP),(DST-PORT,${toString p})),PROXY") sshPorts
    )
    ++ [
      # PT 与特殊业务直连
      "DOMAIN-KEYWORD,m-team,DIRECT"
      "DOMAIN-SUFFIX,m-team.cc,DIRECT"
      "DOMAIN-SUFFIX,m-team.io,DIRECT"
      "DOMAIN-SUFFIX,manfuz.co,DIRECT"
      "DOMAIN-SUFFIX,cloudflare.com,DIRECT"
      "DOMAIN-SUFFIX,nsupdate.info,DIRECT"
      "DOMAIN-SUFFIX,dora.im,DIRECT"
      "DOMAIN-SUFFIX,kxy.ovh,DIRECT"

      # Noctalia IP geolocation and weather: use the local public IP, not the proxy exit.
      "DOMAIN,api.noctalia.dev,DIRECT"
      "DOMAIN,api.open-meteo.com,DIRECT"
      "DOMAIN,invite.linuxdo.org,DIRECT"

      # 拦截广告
      "GEOSITE,category-ads-all,REJECT"
      "GEOIP,ad,REJECT,no-resolve"

      # 局域网直连，防误伤
      "GEOSITE,private,DIRECT"
      "GEOIP,private,DIRECT,no-resolve"

      # 阻断海外 QUIC (UDP 443)，强降 TCP 防视频断流
      "AND,((NETWORK,UDP),(DST-PORT,443),(OR,((GEOSITE,geolocation-!cn),(NOT,((GEOIP,cn)))))),REJECT"
    ]
    ++ userGroupRules
    ++ (
      if userGroupRules == [ ] then
        [
          "GEOSITE,openai,PROXY"
          "GEOSITE,anthropic,PROXY"
          "GEOSITE,google-gemini,PROXY"
          "GEOSITE,netflix,PROXY"
        ]
      else
        [ ]
    )
    ++ [
      # 国外域名与非国内 IP，全走代理（当 PROXY 选 DIRECT 时，全部交由内核 L3 路由表按国家就近加速或走 eth0）
      "GEOSITE,geolocation-!cn,PROXY"
      "AND,((NOT,((GEOIP,cn))),(NOT,((GEOIP,private)))),PROXY"
      "GEOSITE,google,PROXY"

      # 已知国内域名与 IP，全部直连
      "GEOSITE,cn,DIRECT"
      "GEOIP,cn,DIRECT"

      # 兜底代理
      "MATCH,PROXY"
    ];

    dns = {
      enable = true;
      listen = "0.0.0.0:1053";
      ipv6 = true;
      prefer-ipv4 = true;

      enhanced-mode = "redir-host";
      default-nameserver = [
        "https://1.12.12.12/dns-query"
        "https://223.5.5.5/dns-query"
        "https://119.29.29.29/dns-query"
      ];
      nameserver = [
        "https://1.1.1.1/dns-query#PROXY"
        "https://8.8.8.8/dns-query#PROXY"
      ];
      nameserver-policy = {
        # "+.et" = "udp://100.100.100.101#EasyTier-Socks";
        "+.${domain}" = [
          "https://1.1.1.1/dns-query#PROXY"
          "https://1.12.12.12/dns-query"
          "https://223.5.5.5/dns-query"
          "https://119.29.29.29/dns-query"
        ];
        "+.ts" = [
          "100.100.100.100:53"
        ];
        "geosite:cn,apple,private,steam,onedrive" = [
          "https://1.12.12.12/dns-query"
          "https://223.5.5.5/dns-query"
          "https://119.29.29.29/dns-query"
        ];
      };
    };

    tun = {
      enable = true;
      device = "Meta";
      stack = "system";
      auto-redirect = true;
      auto-route = true;
      # 必须设为 false：否则 Mihomo 会将所有代理出站强制绑定 (SO_BINDTODEVICE) 到默认网关物理网卡 (如 Wi-Fi/eth0)，
      # 从而直接绕过内核路由表，导致发往内网 SOCKS5 节点的包被错误扔给家用路由器丢弃
      auto-detect-interface = false;
      inet4_route_address = [
        "0.0.0.0/1"
        "128.0.0.0/1"
      ];
      inet6_route_address = [
        "::/1"
        "8000::/1"
      ];
      exclude-interface = [
        "tailscale0"
        "easytier0"
        "dn42"
        "dn42x-+"
        "xfrm+"
      ];
      route-exclude-address = [
        "100.64.0.0/10"
        "100.42.0.0/10"
        # Keep EasyTier's overlay subnet out of Mihomo's TUN.
        "10.100.0.0/24"
        # Keep overlay subnets out of Mihomo's TUN.
        "172.20.0.0/14"
        "172.31.0.0/16"
        "10.0.0.0/8"
        "fd00::/8"
        # 豁免国内公共 DNS IP，避免自解析查询被 TUN 捕获，保障直连极速解析
        "223.5.5.5/32"
        "223.6.6.6/32"
        "119.29.29.29/32"
        "1.12.12.12/32"
        "180.76.76.76/32"
        "114.114.114.114/32"
      ];
    };

    sniffer = {
      enable = true;
      sniffing = [
        "tls"
        "http"
      ];
      skip-domain = [
        "*.${domain}"
        "*.ts"
        "*.et"
      ];
    };

    geodata = {
      mode = true;
      loader = "memcache";
    };

    geox-url = {
      geosite = "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat";
      geoip = "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat";
      mmdb = "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb";
    };
  };
  yamlFormat = pkgs.formats.yaml { };

  mihomoYamlFile = yamlFormat.generate "mihomo.yaml" mihomoConfig;

  # mihomo-smart reuses the same proxy definitions, groups and rules; it only
  # needs its own endpoint so clients can select the kernel explicitly. Derived
  # from mihomoConfig so the two documents cannot drift apart.
  mihomoSmartConfig = mihomoConfig // {
    # Explicitly bound to loopback: mihomo-smart is a fork, so it must not
    # silently inherit allow-lan/bind-address from the shared document.
    allow-lan = false;
    bind-address = "127.0.0.1";
    external-controller = "127.0.0.1:9090";
  };

  mihomoSmartYamlFile = yamlFormat.generate "mihomo-smart.yaml" mihomoSmartConfig;

  nginxText = ''
    location = /${subscriptionPathToken}/mihomo.yaml {
      alias ${config.sops.templates."subscription/mihomo.yaml".path};
    }

    location = /${subscriptionPathToken}/clash.yaml {
      alias ${config.sops.templates."subscription/mihomo.yaml".path};
    }

    location = /${subscriptionPathToken}/mihomo-smart.yaml {
      alias ${config.sops.templates."subscription/mihomo-smart.yaml".path};
    }

    location = /${subscriptionPathToken}/v2ray.txt {
      alias ${config.sops.templates."subscription/v2ray.txt".path};
    }
  '';

  # This endpoint publishes VLESS URIs; Shadowsocks remains in the Mihomo document.
  v2rayText = lib.concatStringsSep "\n" (
    map (
      node:
      let
        server = publicServer node.server;
        safeName = lib.replaceStrings [ " " "#" "%" ] [ "-" "-" "-" ] node.name;
        transportQuery =
          if cfg.transport == "xhttp" then
            "type=xhttp&path=${lib.escapeURL cfg.xhttpPath}&host=${lib.escapeURL cfg.serverName}&mode=${cfg.xhttpMode}&extra=${
              lib.escapeURL (
                builtins.toJSON (
                  cfg.xhttpExtra
                  // {
                    xmux = cfg.xhttpXmux;
                    uplinkChunkSize = cfg.xhttpUplinkChunkSize;
                    scMaxEachPostBytes = cfg.xhttpScMaxEachPostBytes;
                    scMinPostsIntervalMs = cfg.xhttpScMinPostsIntervalMs;
                  }
                )
              )
            }"
          else
            "type=tcp&flow=xtls-rprx-vision";
      in
      "vless://${
        config.sops.placeholder."xray/uuid"
      }@${server}:${toString node.port}?encryption=none&security=reality&sni=${lib.escapeURL cfg.serverName}&fp=chrome&${transportQuery}&pbk=${
        config.sops.placeholder."xray/public_key"
      }&sid=${config.sops.placeholder."xray/short_id"}#${safeName}"
    ) (lib.filter (node: node.type == "vless") cfg.nodes)
  );
in
{
  options.services.subscriptionPublisher = {
    enable = lib.mkEnableOption "Publish Mihomo and V2Ray subscriptions";

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "sub";
      description = "Subdomain used to expose the subscription endpoints.";
    };

    serverName = lib.mkOption {
      type = lib.types.str;
      default = "speedtest.dora.im";
      description = "SNI/serverName used by all VLESS Reality nodes.";
    };

    transport = lib.mkOption {
      type = lib.types.enum [
        "tcp"
        "xhttp"
      ];
      default = "xhttp";
      description = "VLESS transport; select tcp when rolling all servers back to the legacy sing-box configuration.";
    };

    xhttpPath = lib.mkOption {
      type = lib.types.str;
      default = "/speedtest";
      description = "XHTTP path, which must match the server module's xhttpPath.";
    };

    xhttpMode = lib.mkOption {
      type = lib.types.enum [
        "stream-one"
        "stream-up"
        "packet-up"
      ];
      default = "stream-one";
      description = "XHTTP mode, which must match the server module's xhttpMode.";
    };

    xhttpExtra = lib.mkOption {
      type = lib.types.submodule {
        options = {
          xPaddingBytes = lib.mkOption {
            type = lib.types.str;
            default = "100-1000";
            description = "XHTTP padding length range, shared with the server module.";
          };
          xPaddingObfsMode = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable the XHTTP padding obfuscation mode on both ends.";
          };
          xPaddingPlacement = lib.mkOption {
            type = lib.types.str;
            default = "header";
            description = "Explicit padding placement, required because the two clients have different defaults.";
          };
          xPaddingHeader = lib.mkOption {
            type = lib.types.str;
            default = "X-Padding";
            description = "Shared HTTP header used for XHTTP padding.";
          };
          xPaddingMethod = lib.mkOption {
            type = lib.types.str;
            default = "repeat-x";
            description = "Shared XHTTP padding encoding method.";
          };
        };
      };
      default = { };
      description = "XHTTP padding settings shared by the selected server core and Mihomo.";
    };

    xhttpXmux = lib.mkOption {
      type = lib.types.submodule {
        options = {
          maxConnections = lib.mkOption {
            type = lib.types.str;
            default = "3-3";
            description = "HTTP connection pool size range; do not also set maxConcurrency.";
          };
          hMaxRequestTimes = lib.mkOption {
            type = lib.types.str;
            default = "600-900";
            description = "Requests served per connection before retirement.";
          };
          hMaxReusableSecs = lib.mkOption {
            type = lib.types.str;
            default = "1800-3000";
            description = "Connection reuse lifetime range in seconds.";
          };
          hKeepAlivePeriod = lib.mkOption {
            type = lib.types.int;
            default = 45;
            description = "HTTP/2 keep-alive interval in seconds.";
          };
        };
      };
      default = { };
      description = "Bounded XHTTP client connection reuse; this does not eliminate TCP head-of-line blocking.";
    };

    xhttpUplinkChunkSize = lib.mkOption {
      type = lib.types.str;
      default = "524288-1048576";
      description = "Uplink chunk size range in bytes; helps absorb burst loss on high-RTT links.";
    };

    xhttpScMaxEachPostBytes = lib.mkOption {
      type = lib.types.str;
      default = "524288-1048576";
      description = "Maximum size of a single packet-up POST in bytes, shared with the server module.";
    };

    xhttpScMinPostsIntervalMs = lib.mkOption {
      type = lib.types.str;
      default = "10-30";
      description = "Minimum interval between packet-up POSTs in milliseconds (anti-burst), shared with the server module.";
    };

    healthCheckUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://www.gstatic.com/generate_204";
      description = "URL used by URL-test and load-balance groups.";
    };

    nodes = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule (
          { ... }: {
            options = {
              name = lib.mkOption { type = lib.types.str; };
              server = lib.mkOption {
                type = lib.types.str;
                description = "Server hostname (e.g. fra0) or FQDN (e.g. cu.dora.im)";
              };
              port = lib.mkOption { type = lib.types.port; };
              type = lib.mkOption {
                type = lib.types.enum [
                  "vless"
                  "ss"
                ];
                default = "vless";
                description = "Public proxy protocol";
              };
              cipher = lib.mkOption {
                type = lib.types.str;
                default = "2022-blake3-aes-128-gcm";
                description = "Shadowsocks cipher if type is ss";
              };
              password = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Shadowsocks password if type is ss";
              };
              regions = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "所属地区（如 HK, JP, EU, US 等）";
              };
            };
          }
        )
      );
      default = [ ];
      description = "Node definitions to publish.";
    };

    groups = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule (
          { ... }: {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                description = "策略组名称，例如 UNLOCK, AI, STREAMING 等";
              };
              type = lib.mkOption {
                type = lib.types.str;
                default = "url-test";
                description = "策略组类型 (url-test, fallback, select, load-balance)，默认 url-test";
              };
              url = lib.mkOption {
                type = lib.types.str;
                default = cfg.healthCheckUrl;
                description = "健康检查 URL，默认继承 healthCheckUrl";
              };
              interval = lib.mkOption {
                type = lib.types.int;
                default = 300;
                description = "健康检查间隔 (秒)，默认 300";
              };
              tolerance = lib.mkOption {
                type = lib.types.int;
                default = 20;
                description = "容差延迟 (ms)，默认 20";
              };
              nodes = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "手动指定的机器节点列表（排在最前面，可作为高优先级）";
              };
              groups = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "手动指定的群组列表，支持策略组名、地区名、以及 \"!HK\" 排除语法";
              };
              expandGroups = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "是否将群组展开为底层节点机器。默认 false (直接引用策略组名)";
              };
              proxies = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "自定义 proxies 列表（若显式指定则优先使用，为空则由 nodes + groups 自动生成）";
              };
              rules = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "绑定至该策略组的分流规则列表，随 groups 列表定义顺序依次排入 rules";
              };
            };
          }
        )
      );
      default = [ ];
      description = "用户自定义策略组列表，定义顺序在 YAML 中严格保持。";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.nodes != [ ];
        message = "services.subscriptionPublisher.nodes must not be empty";
      }
      {
        assertion = lib.hasPrefix "/" cfg.xhttpPath;
        message = "services.subscriptionPublisher.xhttpPath must begin with /";
      }
    ];

    sops.secrets."xray/subscription_path_token" = {
      mode = "0400";
    };

    services.nginx = {
      enable = lib.mkDefault true;
      defaultHTTPListenPort = lib.mkDefault config.ports.nginx;
      virtualHosts."${cfg.subdomain}.${config.networking.domain}" = {
        extraConfig = ''
          include ${config.sops.templates."subscription/nginx.conf".path};
        '';
      };
    };

    services.traefik.proxies.subscription-publisher = {
      rule = "Host(`${cfg.subdomain}.${config.networking.domain}`)";
      priority = 1000;
      target = "http://127.0.0.1:${toString config.ports.nginx}";
    };

    sops.templates."subscription/mihomo.yaml" = {
      owner = "nginx";
      mode = "0400";
      file = mihomoYamlFile;
    };

    sops.templates."subscription/mihomo-smart.yaml" = {
      owner = "nginx";
      mode = "0400";
      file = mihomoSmartYamlFile;
    };

    sops.templates."subscription/nginx.conf" = {
      owner = "nginx";
      mode = "0400";
      restartUnits = [ "nginx.service" ];
      content = nginxText;
    };

    sops.templates."subscription/v2ray.txt" = {
      owner = "nginx";
      mode = "0400";
      content = v2rayText;
    };
  };
}
