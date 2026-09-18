{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.atc.router;

  trProperties = pkgs.writeText "traffic_router.properties" ''
    # Traffic Router Configuration for Low-Concurrency High-TTL CDN
    traffic_monitor.bootstrap.hosts=${cfg.trafficMonitorUrl}
    traffic_ops.username=${cfg.trafficOpsUser}
    traffic_ops.hosts=${cfg.trafficOpsUrl}

    # DNS TTL 放宽至 60s，显著降低弱公网 nue0 的并发查询负担 (Task 1)
    dns.zones.ttl=${toString cfg.dns.ttl}
    dns.soa.ttl=${toString cfg.dns.ttl}
    dns.zones.dir=/etc/traffic_router/zones

    # CrStates 轮询周期 (从 Traffic Monitor 获取边缘健康状态)
    traffic_monitor.properties.polling.interval=5000

    # API 与状态接口仅绑定 Tailscale
    api.port=${toString cfg.api.port}
    api.bind.address=${cfg.api.listenAddress}
  '';
in
{
  options.services.atc.router = {
    enable = mkEnableOption "Apache Traffic Control Traffic Router (DNS & HTTP Steering)";

    dns = {
      listenAddress = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Address to bind DNS server (publicly reachable)";
      };

      port = mkOption {
        type = types.port;
        default = 53;
        description = "DNS listening port";
      };

      ttl = mkOption {
        type = types.int;
        default = 60; # 60s (Task 1)
        description = "DNS response TTL in seconds to ease DNS load on nue0";
      };
    };

    api = {
      listenAddress = mkOption {
        type = types.str;
        default = "100.64.0.1";
        description = "Address to bind management and statistics endpoints (Tailscale only)";
      };

      port = mkOption {
        type = types.port;
        default = 3333;
        description = "Internal management port";
      };
    };

    trafficMonitorUrl = mkOption {
      type = types.str;
      default = "http://100.64.0.1:8080";
      description = "Tailscale URL for Traffic Monitor CrStates";
    };

    trafficOpsUrl = mkOption {
      type = types.str;
      default = "https://100.64.0.1:443";
      description = "Tailscale URL for Traffic Ops API";
    };

    trafficOpsUser = mkOption {
      type = types.str;
      default = "traffic_router";
      description = "Service account username for Traffic Router";
    };

    trafficOpsPasswordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing password for Traffic Ops";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.traffic-router;
      description = "Package providing traffic_router binary";
    };
  };

  config = mkIf cfg.enable {
    # 开放公网 DNS 解析端口
    networking.firewall.allowedUDPPorts = [ cfg.dns.port ];
    networking.firewall.allowedTCPPorts = [ cfg.dns.port ];

    users.users.trafficrouter = {
      isSystemUser = true;
      group = "trafficrouter";
      description = "Apache Traffic Router daemon user";
    };
    users.groups.trafficrouter = { };

    systemd.tmpfiles.rules = [
      "d /etc/traffic_router 0750 trafficrouter trafficrouter -"
      "d /etc/traffic_router/zones 0750 trafficrouter trafficrouter -"
      "d /var/log/traffic_router 0750 trafficrouter trafficrouter -"
    ];

    environment.etc."traffic_router/traffic_router.properties".source = trProperties;

    systemd.services.traffic-router = {
      description = "Apache Traffic Control Traffic Router";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      capabilities = "cap_net_bind_service=+ep";

      serviceConfig = {
        Type = "simple";
        User = "trafficrouter";
        Group = "trafficrouter";
        Restart = "always";
        RestartSec = "10s";

        MemoryMax = "512M";
        LimitNOFILE = 65536;

        ExecStart = ''
          ${cfg.package}/bin/traffic_router \
            -conf /etc/traffic_router/traffic_router.properties \
            -dns-port ${toString cfg.dns.port} \
            -dns-addr ${cfg.dns.listenAddress}
        '';
      };
    };
  };
}
