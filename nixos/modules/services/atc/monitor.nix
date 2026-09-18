{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.atc.monitor;

  tmConfigFile = pkgs.writeText "traffic_monitor.cfg" (
    builtins.toJSON {
      traffic_ops_url = cfg.trafficOpsUrl;
      traffic_ops_user = cfg.trafficOpsUser;
      traffic_ops_pass = "";
      traffic_ops_disk_retry_max = 5;
      traffic_ops_retry_interval_ms = 10000;
      serve_read_timeout_ms = 10000;
      serve_write_timeout_ms = 10000;
      health_polling_interval_ms = cfg.healthPollingIntervalMs;
      health_timeout_ms = cfg.healthTimeoutMs;
      health_connection_timeout_ms = cfg.healthConnectionTimeoutMs;
      stat_polling_interval_ms = cfg.statPollingIntervalMs;
      stat_timeout_ms = cfg.statTimeoutMs;
      peer_polling_interval_ms = 20000;
      peer_timeout_ms = 8000;
      http_poll_no_keep_alive = false;
      log_location_error = "stderr";
      log_location_warning = "stderr";
      log_location_info = "null";
      log_location_debug = "null";
      log_location_event = "stdout";
    }
  );
in
{
  options.services.atc.monitor = {
    enable = mkEnableOption "Apache Traffic Control Traffic Monitor daemon";

    listenAddress = mkOption {
      type = types.str;
      default = "100.64.0.1";
      description = "IP address to bind Traffic Monitor (strictly Tailscale overlay IP)";
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port to serve CrStates and TM health stats";
    };

    trafficOpsUrl = mkOption {
      type = types.str;
      default = "https://100.64.0.1:443";
      description = "Traffic Ops API URL on Tailscale overlay";
    };

    trafficOpsUser = mkOption {
      type = types.str;
      default = "traffic_monitor";
      description = "Traffic Ops monitoring service account username";
    };

    trafficOpsPasswordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing password for Traffic Ops";
    };

    healthPollingIntervalMs = mkOption {
      type = types.int;
      default = 20000; # 20 seconds (Task 3: 15s~30s)
      description = "Health check polling interval in ms (relaxed from 1s to avoid DDOSing weak edge nodes)";
    };

    healthTimeoutMs = mkOption {
      type = types.int;
      default = 8000; # 8 seconds (Task 3: tolerate nue0 latency)
      description = "Health probe timeout in ms to tolerate high-latency links";
    };

    healthConnectionTimeoutMs = mkOption {
      type = types.int;
      default = 5000;
      description = "Health probe connection timeout in ms";
    };

    statPollingIntervalMs = mkOption {
      type = types.int;
      default = 60000; # 60 seconds
      description = "Cache statistics polling interval in ms";
    };

    statTimeoutMs = mkOption {
      type = types.int;
      default = 10000;
      description = "Cache statistics timeout in ms";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.trafficcontrol;
      description = "Package providing traffic_monitor binary";
    };
  };

  config = mkIf cfg.enable {
    users.users.trafficmonitor = {
      isSystemUser = true;
      group = "trafficmonitor";
      description = "Apache Traffic Monitor daemon user";
    };
    users.groups.trafficmonitor = { };

    systemd.tmpfiles.rules = [
      "d /etc/traffic_monitor 0750 trafficmonitor trafficmonitor -"
      "d /var/log/traffic_monitor 0750 trafficmonitor trafficmonitor -"
    ];

    environment.etc."traffic_monitor/traffic_monitor.cfg".source = tmConfigFile;

    systemd.services.traffic-monitor = {
      description = "Apache Traffic Control Traffic Monitor";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "trafficmonitor";
        Group = "trafficmonitor";
        Restart = "always";
        RestartSec = "10s";

        # 仅绑定 Tailscale 内网地址与端口
        ExecStart = ''
          ${cfg.package}/bin/traffic_monitor \
            -opsCfg /etc/traffic_monitor/traffic_monitor.cfg \
            -config /etc/traffic_monitor/traffic_monitor.cfg \
            -address ${cfg.listenAddress}:${toString cfg.port}
        '';
      };
    };
  };
}
