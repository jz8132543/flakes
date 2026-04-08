{
  config,
  lib,
  ...
}:

let
  cfg = config.services.subscriptionPublisher;
  subscriptionPathToken = config.sops.placeholder."xray/subscription_path_token";
  regionNames = [
    "HK"
    "JP"
    "EU"
    "US"
  ];

  mkNode = node: {
    inherit (node) name server port;
    type = "vless";
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
    client-fingerprint = "ios";
  };

  mkRegionGroup = region: {
    name = region;
    type = "url-test";
    url = cfg.healthCheckUrl;
    interval = 300;
    tolerance = 20;
    proxies = map (node: node.name) (lib.filter (node: builtins.elem region node.regions) cfg.nodes);
  };

  regionGroups = lib.filter (group: group != null) (
    map (
      region:
      let
        proxies = map (node: node.name) (lib.filter (node: builtins.elem region node.regions) cfg.nodes);
      in
      if proxies == [ ] then null else mkRegionGroup region
    ) regionNames
  );

  regionGroupNames = map (group: group.name) regionGroups;

  mihomoConfig = {
    mixed-port = 7890;
    mode = "Rule";
    log-level = "info";
    allow-lan = true;
    bind-address = "127.0.0.1";
    ipv6 = false;
    udp = true;
    unified-delay = true;
    tcp-concurrent = true;
    find-process-mode = "strict";
    global-client-fingerprint = "random";
    external-controller = "127.0.0.1:9090";
    secret = "";

    proxies = map mkNode cfg.nodes;

    proxy-groups = regionGroups
    ++ [
      {
        name = "ALL-AUTO-FASTEST";
        type = "url-test";
        url = cfg.healthCheckUrl;
        interval = 300;
        tolerance = 20;
        proxies = map (node: node.name) cfg.nodes;
      }
      {
        name = "SPEED-BOOST";
        type = "load-balance";
        url = cfg.healthCheckUrl;
        interval = 300;
        strategy = "consistent-hashing";
        proxies = map (node: node.name) cfg.nodes;
      }
      {
        name = "PROXY";
        type = "select";
        proxies = [
          "ALL-AUTO-FASTEST"
          "SPEED-BOOST"
        ]
        ++ regionGroupNames
        ++ [
          "DIRECT"
        ];
      }
    ];

    rules = [
      # 防环路，直接放行 EasyTier 核心进程
      "PROCESS-NAME,easytier-core,DIRECT"

      # PT 与特殊业务直连
      "DOMAIN-KEYWORD,m-team,DIRECT"
      "DOMAIN-SUFFIX,m-team.cc,DIRECT"
      "DOMAIN-SUFFIX,m-team.io,DIRECT"
      "DOMAIN-SUFFIX,manfuz.co,DIRECT"
      "DOMAIN-SUFFIX,cloudflare.com,DIRECT"
      "DOMAIN-SUFFIX,nsupdate.info,DIRECT"
      "DOMAIN-SUFFIX,dora.im,DIRECT"

      # 拦截广告
      "GEOSITE,category-ads-all,REJECT"
      "GEOIP,ad,REJECT,no-resolve"

      # EasyTier 专属路由与沙盒隔离
      "DOMAIN-SUFFIX,et,EasyTier-Socks"
      "IP-CIDR,10.100.0.0/24,EasyTier-Socks,no-resolve"

      # 局域网直连，防误伤
      "GEOSITE,private,DIRECT"
      "GEOIP,private,DIRECT,no-resolve"

      # 阻断海外 QUIC (UDP 443)，强降 TCP 防视频断流
      "AND,((NETWORK,UDP),(DST-PORT,443),(OR,((GEOSITE,geolocation-!cn),(NOT,((GEOIP,cn)))))),REJECT"

      # 国外域名与非国内 IP，全走代理
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
      listen = "127.0.0.1:1053";
      enhanced-mode = "redir-host";
      default-nameserver = [
        "223.5.5.5"
        "1.12.12.12"
      ];
      proxy-server-nameserver = [
        "223.5.5.5"
        "1.12.12.12"
      ];
      nameserver = [
        "https://1.1.1.1/dns-query#PROXY"
        "https://9.9.9.9/dns-query#PROXY"
      ];
      nameserver-policy = {
        "+.et" = "udp://100.100.100.101#EasyTier-Socks";
        "geosite:cn,apple,private,steam,onedrive" = [
          "tls://223.5.5.5"
          "tls://1.12.12.12"
        ];
      };
    };
  };

  mihomoText = lib.generators.toYAML { } mihomoConfig;

  nginxText = ''
    location = / {
      return 302 https://${cfg.subdomain}.${config.networking.domain}/${subscriptionPathToken}/mihomo.yaml;
    }

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
        safeName = lib.replaceStrings [ " " "#" "%" ] [ "-" "-" "-" ] node.name;
      in
      "vless://${
        config.sops.placeholder."xray/uuid"
      }@${node.server}:${toString node.port}?encryption=none&security=reality&sni=${cfg.serverName}&fp=ios&type=tcp&flow=xtls-rprx-vision&pbk=${
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
      default = "gateway.icloud.com";
      description = "SNI/serverName used by all VLESS Reality nodes.";
    };

    healthCheckUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://www.gstatic.com/generate_204";
      description = "URL used by URL-test and load-balance groups.";
    };

    nodes = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule (
          { ... }:
          {
            options = {
              name = lib.mkOption { type = lib.types.str; };
              server = lib.mkOption { type = lib.types.str; };
              port = lib.mkOption { type = lib.types.port; };
              regions = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
              };
            };
          }
        )
      );
      default = [ ];
      description = "Node definitions to publish.";
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
      content = mihomoText;
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
