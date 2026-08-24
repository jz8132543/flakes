{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.adguard-mosdns;

  geositeCn = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/direct-list.txt";
    sha256 = "1y6zbm7bidwmkh003m736h75vmlnf3v8m5wi7jd7ddn3plh4qhhf";
  };

  geositeGeolocationNoncn = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/proxy-list.txt";
    sha256 = "1ir5bsr74x21pmhf4bn199xwmz195wfz35gmh9d1z8z6xgnp5rcx";
  };

  # Mosdns configuration (v5 format)
  mosdnsConfig = pkgs.writeText "mosdns-config.yaml" ''
    log:
      level: info

    plugins:
      # Data providers
      - tag: geosite_cn
        type: domain_set
        args:
          files:
            - "${geositeCn}"

      - tag: geosite_geolocation_noncn
        type: domain_set
        args:
          files:
            - "${geositeGeolocationNoncn}"

      # ECS 伪装插件：将发往国内 DNS 的请求强制加上国内 IP 的子网信息
      # 114.114.114.114 是国内知名 DNS，这里借用它的网段来骗取国内 CDN 节点
      - tag: ecs_cn
        type: ecs_handler
        args:
          forward: false 
          preset: 114.114.114.114
          mask4: 24

      # Caching plugin
      - tag: cache
        type: cache
        args:
          size: 10240
          lazy_cache_ttl: 86400
          dump_file: "/var/cache/mosdns/cache.dump"
          dump_interval: 600

      # Forward to domestic DNS
      - tag: forward_local
        type: forward
        args:
          concurrent: 2
          upstreams:
            - addr: "223.5.5.5"
            - addr: "119.29.29.29"

      # Forward to remote (overseas) DNS
      - tag: forward_remote
        type: forward
        args:
          concurrent: 2
          upstreams:
            - addr: "https://1.1.1.1/dns-query"
              dial_addr: "1.1.1.1"
            - addr: "https://8.8.8.8/dns-query"
              dial_addr: "8.8.8.8"

      # 国内解析流程：先附上国内 ECS IP，再去请求国内上游
      - tag: sequence_local
        type: sequence
        args:
          - exec: $ecs_cn
          - exec: $forward_local

      # Fallback logic
      - tag: fallback
        type: fallback
        args:
          primary: sequence_local
          secondary: forward_remote
          threshold: 500
          always_standby: true

      # Main sequence
      - tag: main_sequence
        type: sequence
        args:
          - exec: $cache
          - matches:
              - qname $geosite_cn
            exec: $sequence_local
          - matches:
              - qname $geosite_geolocation_noncn
            exec: $forward_remote
          - exec: $fallback

      # Servers
      - tag: udp_server
        type: udp_server
        args:
          entry: main_sequence
          listen: "127.0.0.1:5333"

      - tag: tcp_server
        type: tcp_server
        args:
          entry: main_sequence
          listen: "127.0.0.1:5333"
  '';

in
{
  options.services.adguard-mosdns = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Adguard Home + Mosdns DNS server tailored for China";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 53;
      description = "The port AdguardHome will listen on.";
    };
    webPort = lib.mkOption {
      type = lib.types.port;
      default = 3053;
      description = "The port for the AdGuard Home Web UI.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Adguard Home Configuration
    services.adguardhome = {
      enable = true;
      port = cfg.webPort;
      settings = {
        dns = {
          bind_hosts = [ "0.0.0.0" ];
          port = 5300; # Internal bind port to avoid conflict with dnsmasq
          # 核心上游配置
          upstream_dns = [
            "[/mag/]100.100.100.100" # Tailscale MagicDNS
            "127.0.0.1:5333" # Mosdns
          ];
          bootstrap_dns = [
            "223.5.5.5"
            "119.29.29.29"
          ];
          # 并行请求上游
          upstream_mode = "parallel";

          # 缓存设置（由于Mosdns已经有了非常完善的缓存，AGH这里的缓存可以相对减小或关闭，以Mosdns为准）
          cache_size = 4194304;

          # 去广告规则
          filters = [
            {
              enabled = true;
              url = "https://anti-ad.net/easylist.txt";
              name = "anti-AD";
              id = 1;
            }
            {
              enabled = true;
              url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
              name = "AdGuard DNS filter";
              id = 2;
            }
            {
              enabled = true;
              url = "https://easylist-downloads.adblockplus.org/easylistchina.txt";
              name = "EasyList China";
              id = 3;
            }
          ];
        };
        tls = {
          allow_unencrypted_doh = true;
        };
      };
    };

    # Mosdns Systemd Service Wrapper
    systemd.services.mosdns = {
      description = "Mosdns DNS forwarder";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.mosdns}/bin/mosdns start -c ${mosdnsConfig}";
        Restart = "always";
        DynamicUser = true;
        StateDirectory = "mosdns";
        CacheDirectory = "mosdns";
      };
    };

    # Open firewall ports
    networking.firewall = {
      allowedTCPPorts = [
        cfg.port
        5300
        cfg.webPort
      ];
      allowedUDPPorts = [
        cfg.port
        5300
      ];
    };

    # Redirect external DNS traffic to internal AdGuardHome port 5300 using nftables
    networking.nftables.tables.adguard-dns = {
      family = "inet";
      content = ''
        chain prerouting {
          type nat hook prerouting priority dstnat; policy accept;
          iifname "tailscale0" udp dport ${toString cfg.port} counter redirect to :5300
          iifname "tailscale0" tcp dport ${toString cfg.port} counter redirect to :5300
          iifname "ens*" udp dport ${toString cfg.port} counter redirect to :5300
          iifname "ens*" tcp dport ${toString cfg.port} counter redirect to :5300
          iifname "eth*" udp dport ${toString cfg.port} counter redirect to :5300
          iifname "eth*" tcp dport ${toString cfg.port} counter redirect to :5300
        }
      '';
    };

    services.traefik.proxies.adguard-mosdns = lib.mkIf (config.services.traefik.enable or false) {
      rule = "Host(`dns.${config.networking.domain}`)";
      target = "https://127.0.0.1:3054";
    };

    services.traefik.tcpProxies.adguard-dot = lib.mkIf (config.services.traefik.enable or false) {
      rule = "HostSNI(`dns.${config.networking.domain}`)";
      target = "127.0.0.1:5300";
      entryPoints = [ "dot" ];
      tls = true;
      tlsOptions = "dot-tls";
    };
  };
}
