{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.atc.monitor;
  runtimeConfig = "/run/traffic-monitor/traffic_monitor.cfg";

  tmConfigFile = pkgs.writeText "traffic_monitor.cfg" (
    builtins.toJSON {
      httpListener = "${cfg.listenAddress}:${toString cfg.port}";
      static_file_dir = "${cfg.package}/share/traffic_monitor/static";
      crconfig_backup_file = "/var/lib/traffic_monitor/crconfig.backup";
      tmconfig_backup_file = "/var/lib/traffic_monitor/tmconfig.backup";
      crconfig_history_count = 100;
      url = cfg.trafficOpsUrl;
      username = cfg.trafficOpsUser;
      insecure = cfg.trafficOpsInsecure;
      password = "";
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
      connection_time_warning_ms = cfg.connectionTimeWarningMs;
      connection_time_timeout_ms = cfg.connectionTimeTimeoutMs;
      health_penalty_enabled = cfg.healthPenaltyEnabled;
      health_penalty_window = cfg.healthPenaltyWindow;
      health_penalty_threshold = cfg.healthPenaltyThreshold;
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
      default = "0.0.0.0";
      description = "IP address to bind Traffic Monitor. Defaults to all interfaces.";
    };

    port = mkOption {
      type = types.port;
      default = 8087;
      description = "Port to serve CrStates and TM health stats.";
    };

    trafficOpsUrl = mkOption {
      type = types.str;
      default =
        if (config.services.atc.ops.enable or false) then
          "https://127.0.0.1:${toString config.services.atc.ops.port}"
        else
          "https://ops.${config.networking.domain}";
      defaultText = "if ops.enable then local 127.0.0.1:port else https://ops.<networking.domain>";
      description = "Traffic Ops API URL. Must use HTTPS (Traefik terminates TLS).";
    };

    trafficOpsUser = mkOption {
      type = types.str;
      default = "t3c-sync";
      description = "Traffic Ops service account username for monitoring.";
    };

    trafficOpsInsecure = mkOption {
      type = types.bool;
      default = config.services.atc.ops.enable or false;
      defaultText = "true if ops.enable else false";
      description = "Skip certificate verification when connecting to Traffic Ops.";
    };

    healthPollingIntervalMs = mkOption {
      type = types.int;
      default = 20000;
      description = "Health check polling interval in ms (relaxed from 1s to avoid overloading weak edge nodes).";
    };

    healthTimeoutMs = mkOption {
      type = types.int;
      default = 8000;
      description = "Health probe timeout in ms (generous for high-latency links).";
    };

    healthConnectionTimeoutMs = mkOption {
      type = types.int;
      default = 5000;
      description = "Health probe connection timeout in ms.";
    };

    statPollingIntervalMs = mkOption {
      type = types.int;
      default = 60000;
      description = "Cache statistics polling interval in ms.";
    };

    statTimeoutMs = mkOption {
      type = types.int;
      default = 10000;
      description = "Cache statistics timeout in ms.";
    };

    connectionTimeWarningMs = mkOption {
      type = types.int;
      default = 1000;
      description = "Connection time warning threshold in ms. Edges above this are marked degraded in crconfig.";
    };

    connectionTimeTimeoutMs = mkOption {
      type = types.int;
      default = 5000;
      description = "Connection time timeout threshold in ms. Edges exceeding this are marked OFFLINE.";
    };

    healthPenaltyEnabled = mkOption {
      type = types.bool;
      default = true;
      description = "Enable health penalty for high-latency or unstable edge nodes.";
    };

    healthPenaltyWindow = mkOption {
      type = types.int;
      default = 60000;
      description = "Rolling window in ms for health penalty calculation.";
    };

    healthPenaltyThreshold = mkOption {
      type = types.int;
      default = 3;
      description = "Number of degraded health events within the window before deprioritizing the node.";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.trafficcontrol;
      description = "Package providing traffic_monitor binary.";
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
      "d /var/lib/traffic_monitor 0750 trafficmonitor trafficmonitor -"
    ];

    environment.etc."traffic_monitor/traffic_monitor.cfg".source = tmConfigFile;
    sops.secrets."atc/ops_password" = {
      owner = "trafficops";
      group = "trafficops";
      mode = "0440";
    };

    systemd.services.traffic-monitor = {
      description = "Apache Traffic Control Traffic Monitor";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      preStart = ''
        if [ ! -s ${config.sops.secrets."atc/ops_password".path} ]; then
          echo "Traffic Monitor Traffic Ops password secret is missing or empty" >&2
          exit 1
        fi
        ${pkgs.jq}/bin/jq --rawfile password ${config.sops.secrets."atc/ops_password".path} \
          '.password = ($password | rtrimstr("\n") | rtrimstr("\r"))' \
          ${tmConfigFile} > ${runtimeConfig}
        chown trafficmonitor:trafficmonitor ${runtimeConfig}
        chmod 0600 ${runtimeConfig}
      '';

      serviceConfig = {
        Type = "simple";
        User = "trafficmonitor";
        Group = "trafficmonitor";
        SupplementaryGroups = [ "trafficops" ];
        RuntimeDirectory = "traffic-monitor";
        RuntimeDirectoryMode = "0750";
        Restart = "always";
        RestartSec = "10s";
        StartLimitIntervalSec = 0;
        MemoryMax = "256M";
        LimitNOFILE = 65536;

        ExecStart = ''
          ${cfg.package}/bin/traffic_monitor \
            -opsCfg ${runtimeConfig} \
            -config ${runtimeConfig}
        '';
      };
      path = [ pkgs.nettools ];
    };
  };
}
