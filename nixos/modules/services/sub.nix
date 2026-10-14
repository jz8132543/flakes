{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.subscriptionPublisher;
  domain = config.networking.domain;
  subscriptionPathToken = config.sops.placeholder."xray/subscription_path_token";

  selfData = config.lib.self.data or (lib.importJSON ../../../../lib/data/data.json);
  allHostsData = selfData.hosts or { };

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

  dn42Server = server: "${serverHost server}.dn42";

  # 判断节点是否自动裂变为 DN42 节点（例如中转节点 *-kxy 不自动生成 DN42）
  shouldGenDn42 = node: node.enableDn42 && !lib.hasInfix "kxy" node.name;

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
        network = "tcp";
        tls = true;
        udp = true;
        flow = "xtls-rprx-vision";
        servername = cfg.serverName;
        reality-opts = {
          public-key = config.sops.placeholder."xray/public_key";
          short-id = config.sops.placeholder."xray/short_id";
        };
        client-fingerprint = "chrome";
      };

  getDn42Ip =
    serverName:
    let
      h = serverHost serverName;
      hData = allHostsData.${h} or { };
      v4s = hData.dn42_addresses_v4 or [ ];
    in
    if v4s != [ ] then lib.head v4s else dn42Server serverName;

  # DN42 内网节点：因内部网络天然受 WireGuard/XFRM 隧道加密，直接使用高性能免加密 SOCKS5 协议
  # 使用真实 DN42 IP 作为 server，避免 Mihomo 的 proxy-server-nameserver (223.5.5.5) 因无法解析 .dn42 导致 NXDOMAIN 超时
  mkDn42Node = node: {
    name = "${node.name}-DN42";
    server = getDn42Ip node.server;
    port = if node.socksPort != null then node.socksPort else cfg.socksPort;
    type = "socks5";
    udp = true;
  };

  publicNodes = map mkPublicNode cfg.nodes;
  dn42Nodes = map mkDn42Node (lib.filter shouldGenDn42 cfg.nodes);
  allProxies = publicNodes ++ dn42Nodes;

  publicNodeNames = map (n: n.name) publicNodes;
  dn42NodeNames = map (n: n.name) dn42Nodes;
  allNodeNames = publicNodeNames ++ dn42NodeNames;

  # 双轨区域策略组：针对每个 Region 生成 <REGION>（公网）和 <REGION>-DN42（内网）
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

  mkDn42RegionGroup = region: {
    name = "${region}-DN42";
    type = "url-test";
    url = cfg.healthCheckUrl;
    interval = 120;
    tolerance = 20;
    proxies = map (node: "${node.name}-DN42") (
      lib.filter (node: shouldGenDn42 node && builtins.elem region (getNodeRegions node)) cfg.nodes
    );
  };

  publicRegionGroups = lib.filter (g: g.proxies != [ ]) (map mkPublicRegionGroup regionNames);
  dn42RegionGroups = lib.filter (g: g.proxies != [ ]) (map mkDn42RegionGroup regionNames);

  allRegionGroupNames = (map (g: g.name) publicRegionGroups) ++ (map (g: g.name) dn42RegionGroups);

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
          lib.filter (r: r != excluded && r != "${excluded}-DN42") allRegionGroupNames
        else
          [ g ]
      ) groups;

      expandedNodeNames =
        if expandGroups then
          lib.concatMap (
            g:
            if builtins.elem g regionNames then
              map (n: n.name) (lib.filter (n: builtins.elem g (getNodeRegions n)) cfg.nodes)
            else if lib.hasSuffix "-DN42" g && builtins.elem (lib.removeSuffix "-DN42" g) regionNames then
              let
                baseRegion = lib.removeSuffix "-DN42" g;
              in
              map (n: "${n.name}-DN42") (
                lib.filter (n: shouldGenDn42 n && builtins.elem baseRegion (getNodeRegions n)) cfg.nodes
              )
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

  # 三大汇总策略组：ALL, DN42-ONLY, PUBLIC-ONLY
  summaryGroups = [
    {
      name = "ALL";
      type = "url-test";
      url = cfg.healthCheckUrl;
      interval = 300;
      tolerance = 20;
      proxies = allNodeNames;
    }
  ]
  ++ lib.optional (dn42NodeNames != [ ]) {
    name = "DN42-ONLY";
    type = "url-test";
    url = cfg.healthCheckUrl;
    interval = 120;
    tolerance = 20;
    proxies = dn42NodeNames;
  }
  ++ [
    {
      name = "PUBLIC-ONLY";
      type = "url-test";
      url = cfg.healthCheckUrl;
      interval = 300;
      tolerance = 20;
      proxies = publicNodeNames;
    }
  ];

  # 当用户未自定义 AI 规则时，默认创建的非 HK AI/流媒体专用组（优先走 DN42 节点）

  # 自动提取所有节点 *.dn42 映射字典，直接写入 Mihomo hosts 配置
  dn42HostsMapping = lib.foldr (
    name: acc:
    let
      hData = allHostsData.${name} or { };
      v4s = hData.dn42_addresses_v4 or [ ];
    in
    if v4s != [ ] then acc // { "${name}.dn42" = lib.head v4s; } else acc
  ) { } (builtins.attrNames allHostsData);

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
    global-client-fingerprint = "random";
    external-controller = "0.0.0.0:9090";
    external-ui = "./dashboard";
    redir-port = 9797;
    tproxy-port = 9898;
    secret = "";

    # 注入内网 *.dn42 hosts 解析，确保所有订阅客户端秒级直达 DN42 Loopback IP
    hosts = dn42HostsMapping;

    # 包含公网节点及 DN42 SOCKS5 节点
    proxies = allProxies;

    proxy-groups = [
      # GLOBAL 全局组：用于 Mihomo 切换到全局模式（Global）时的统一出口，默认遵循 PROXY
      {
        name = "GLOBAL";
        type = "select";
        proxies = [
          "PROXY"
          "ALL"
          "PUBLIC-ONLY"
        ]
        ++ lib.optional (dn42NodeNames != [ ]) "DN42-ONLY"
        ++ (map (g: g.name) userGroupDefs)
        ++ allRegionGroupNames
        ++ [ "DIRECT" ];
      }

      # PROXY 规则代理主选择组：保留 全部、公网、DN42 以及用户自定义组与各地区组
      {
        name = "PROXY";
        type = "select";
        proxies = [
          "ALL"
          "PUBLIC-ONLY"
        ]
        ++ lib.optional (dn42NodeNames != [ ]) "DN42-ONLY";
        # ++ (map (g: g.name) userGroupDefs)
        # ++ allRegionGroupNames;
      }
    ]
    ++ userGroupDefs
    ++ summaryGroups
    ++ publicRegionGroups
    ++ dn42RegionGroups;

    rules = [
      # 绕过本机的 microsocks / sing-box 代理，防止循环或被 mihomo 捕获导致 IP 变成节点 IP
      "UID,999,DIRECT"
      "PROCESS-NAME,microsocks,DIRECT"
      "PROCESS-NAME,sing-box,DIRECT"

      # 防环路与直连放行：IPsec/IKE (charon) 与 BIRD 路由守护进程
      "PROCESS-NAME,charon,DIRECT"
      "PROCESS-NAME,charon-systemd,DIRECT"
      "PROCESS-NAME,bird,DIRECT"

      # 放行 IPsec 协商 (500/4500) 与 Babel IGP (6696) 端口
      "DST-PORT,500,DIRECT"
      "DST-PORT,4500,DIRECT"
      "DST-PORT,6696,DIRECT"

      # 放行 SSH 端口直连
      "DST-PORT,22,DIRECT"
      "DST-PORT,1022,DIRECT"

      # DN42 专用内网段直连，交由内核 Babel 路由表处理，绝不进代理环路
      "IP-CIDR,172.20.0.0/14,DIRECT,no-resolve"
      "IP-CIDR,172.31.0.0/16,DIRECT,no-resolve"
      "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve"
      "IP-CIDR,fd00::/8,DIRECT,no-resolve"

      # PT 与特殊业务直连
      "DOMAIN-KEYWORD,m-team,DIRECT"
      "DOMAIN-SUFFIX,m-team.cc,DIRECT"
      "DOMAIN-SUFFIX,m-team.io,DIRECT"
      "DOMAIN-SUFFIX,manfuz.co,DIRECT"
      "DOMAIN-SUFFIX,cloudflare.com,DIRECT"
      "DOMAIN-SUFFIX,nsupdate.info,DIRECT"
      "DOMAIN-SUFFIX,dora.im,DIRECT"
      "IP-CIDR,1.1.1.1/32,DIRECT,no-resolve"
      "IP-CIDR,1.0.0.1/32,DIRECT,no-resolve"
      "IP-CIDR,9.9.9.9/32,DIRECT,no-resolve"

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
      hosts = dn42HostsMapping;
      listen = "0.0.0.0:1053";
      ipv6 = true;
      prefer-ipv4 = true;

      enhanced-mode = "redir-host";
      default-nameserver = [
        "223.5.5.5"
        "1.12.12.12"
        "https://223.5.5.5/dns-query"
        "https://1.12.12.12/dns-query"
      ];
      proxy-server-nameserver = [
        "223.5.5.5"
        "1.12.12.12"
        "https://223.5.5.5/dns-query"
        "https://1.12.12.12/dns-query"
      ];
      nameserver = [
        "https://1.1.1.1/dns-query#PROXY"
        "https://9.9.9.9/dns-query#PROXY"
      ];
      nameserver-policy = {
        # "+.et" = "udp://100.100.100.101#EasyTier-Socks";
        "geosite:cn,apple,private,steam,onedrive" = [
          "https://223.5.5.5/dns-query"
          "https://1.12.12.12/dns-query"
          "tls://223.5.5.5"
          "tls://1.12.12.12"
        ];
      };
    };

    tun = {
      enable = true;
      stack = "system";
      auto-redirect = true;
      auto-route = true;
      # 必须设为 false：否则 Mihomo 会将所有代理出站强制绑定 (SO_BINDTODEVICE) 到默认网关物理网卡 (如 Wi-Fi/eth0)，
      # 从而直接绕过内核路由表，导致发往 DN42 内网 SOCKS5 节点的包被错误扔给家用路由器丢弃
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
      ]
      ++ (lib.optionals (config ? services && config.services ? dn42 && config.services.dn42.enable) (
        [ "dn42" ]
        ++ (map (name: "dn42x-${lib.substring 0 9 name}") (
          builtins.attrNames (config.services.dn42.mesh.nodes or { })
        ))
      ));
      route-exclude-address = [
        "100.64.0.0/10"
        "100.42.0.0/10"
        # Keep EasyTier's overlay subnet out of Mihomo's TUN.
        "10.100.0.0/24"
        # Keep DN42 subnets out of Mihomo's TUN.
        "172.20.0.0/14"
        "172.31.0.0/16"
        "10.0.0.0/8"
        "fd00::/8"
      ];
    };

    sniffer = {
      enable = true;
      sniffing = [
        "tls"
        "http"
      ];
      skip-domain = [
        "*.dora.im"
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

  nginxText = ''
    location = /${subscriptionPathToken}/mihomo.yaml {
      alias ${config.sops.templates."subscription/mihomo.yaml".path};
    }

    location = /${subscriptionPathToken}/clash.yaml {
      alias ${config.sops.templates."subscription/mihomo.yaml".path};
    }

    location = /${subscriptionPathToken}/v2ray.txt {
      alias ${config.sops.templates."subscription/v2ray.txt".path};
    }
  '';

  v2rayText = lib.concatStringsSep "\n" (
    map (
      node:
      let
        server = publicServer node.server;
        safeName = lib.replaceStrings [ " " "#" "%" ] [ "-" "-" "-" ] node.name;
      in
      "vless://${
        config.sops.placeholder."xray/uuid"
      }@${server}:${toString node.port}?encryption=none&security=reality&sni=${cfg.serverName}&fp=chrome&type=tcp&flow=xtls-rprx-vision&pbk=${
        config.sops.placeholder."xray/public_key"
      }&sid=${config.sops.placeholder."xray/short_id"}#${safeName}"
    ) cfg.nodes
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
      default = "assets.msn.com";
      description = "SNI/serverName used by all VLESS Reality nodes.";
    };

    healthCheckUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://www.gstatic.com/generate_204";
      description = "URL used by URL-test and load-balance groups.";
    };

    socksPort = lib.mkOption {
      type = lib.types.port;
      default = 1080;
      description = "Default SOCKS5 port for DN42 internal nodes.";
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
              socksPort = lib.mkOption {
                type = lib.types.nullOr lib.types.port;
                default = null;
                description = "Custom SOCKS5 port for DN42 node (defaults to cfg.socksPort)";
              };
              enableDn42 = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Whether to auto-generate a DN42 SOCKS5 proxy node (auto-disabled if name contains kxy)";
              };
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
    ];

    sops.secrets."xray/subscription_path_token" = {
      mode = "0444";
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
      mode = "0444";
      file = mihomoYamlFile;
    };

    sops.templates."subscription/nginx.conf" = {
      owner = "nginx";
      mode = "0444";
      restartUnits = [ "nginx.service" ];
      content = nginxText;
    };

    sops.templates."subscription/v2ray.txt" = {
      owner = "nginx";
      mode = "0444";
      content = v2rayText;
    };
  };
}
