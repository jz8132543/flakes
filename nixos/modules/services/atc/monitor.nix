{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.atc.monitor;
  runtimeOpsConfig = "/run/traffic-monitor/traffic_ops.cfg";
  # TC 8.0.2 decodes these with two separate structs. Unknown JSON keys are
  # silently ignored upstream, so keep the contracts separate and explicit.
  opsConfig = {
    httpListener = "${cfg.listenAddress}:${toString cfg.port}";
    url = cfg.trafficOpsUrl;
    username = cfg.trafficOpsUser;
    insecure = cfg.trafficOpsInsecure;
    password = "";
  };
  tmConfig = {
    static_file_dir = "${cfg.package}/share/traffic_monitor/static";
    crconfig_backup_file = "/var/lib/traffic_monitor/crconfig.backup";
    tmconfig_backup_file = "/var/lib/traffic_monitor/tmconfig.backup";
    crconfig_history_count = 100;
    traffic_ops_disk_retry_max = 5;
    traffic_ops_min_retry_interval_ms = 100;
    traffic_ops_max_retry_interval_ms = 10000;
    monitor_config_polling_interval_ms = 5000;
    serve_read_timeout_ms = 10000;
    serve_write_timeout_ms = 10000;
    http_timeout_ms = cfg.httpTimeoutMs;
    cache_polling_protocol = "both";
    http_polling_format = "application/json";
    distributed_polling = false;
    stat_polling = true;
    health_flush_interval_ms = 200;
    stat_flush_interval_ms = 200;
    stat_buffer_interval_ms = 0;
    log_location_error = "stderr";
    log_location_warning = "stderr";
    log_location_info = "null";
    log_location_debug = "null";
    log_location_event = "stdout";
  };
  # config/config.go Config + UnmarshalJSON and handler/handler.go OpsConfig.
  supportedTMFields = [
    "cache_polling_protocol"
    "crconfig_backup_file"
    "crconfig_history_count"
    "distributed_polling"
    "health_flush_interval_ms"
    "http_polling_format"
    "http_timeout_ms"
    "log_location_access"
    "log_location_debug"
    "log_location_error"
    "log_location_event"
    "log_location_info"
    "log_location_warning"
    "max_events"
    "monitor_config_polling_interval_ms"
    "peer_optimistic_quorum_min"
    "serve_read_timeout_ms"
    "serve_write_timeout_ms"
    "short_hostname_override"
    "stat_buffer_interval_ms"
    "stat_flush_interval_ms"
    "static_file_dir"
    "stat_polling"
    "tmconfig_backup_file"
    "traffic_ops_disk_retry_max"
    "traffic_ops_min_retry_interval_ms"
    "traffic_ops_max_retry_interval_ms"
  ];
  supportedOpsFields = [
    "cdnName"
    "certFile"
    "httpListener"
    "httpsListener"
    "insecure"
    "keyFile"
    "password"
    "url"
    "username"
    "usingDummyTO"
  ];
  tmConfigFile = pkgs.writeText "traffic_monitor.cfg" (builtins.toJSON tmConfig);
  opsConfigFile = pkgs.writeText "traffic_monitor-ops.cfg" (builtins.toJSON opsConfig);
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
      type = types.ints.positive;
      default = 5000;
      description = "Health interval in ms, published by local Ops as heartbeat.polling.interval (not a Monitor JSON setting).";
    };

    httpTimeoutMs = mkOption {
      type = types.ints.positive;
      default = 3000;
      description = "Total HTTP timeout in ms for Monitor peer, health and statistics requests.";
    };

    healthConnectionTimeoutMs = mkOption {
      type = types.ints.positive;
      default = 3000;
      description = "Per-cache total HTTP timeout in ms, published by local Ops as health.connection.timeout; TC 8.0.2 overrides http_timeout_ms with this value for health and statistics requests.";
    };

    statPollingIntervalMs = mkOption {
      type = types.ints.positive;
      default = 60000;
      description = "Statistics interval in ms, published by local Ops as health.polling.interval; TC 8.0.2 does not read stat.polling.interval.";
    };

    peerPollingIntervalMs = mkOption {
      type = types.ints.positive;
      default = 20000;
      description = "Peer interval in ms, published by local Ops as peers.polling.interval.";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.trafficcontrol;
      description = "Package providing traffic_monitor binary.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion =
          all (name: elem name supportedTMFields) (attrNames tmConfig)
          && all (name: elem name supportedOpsFields) (attrNames opsConfig);
        message = "Traffic Monitor configuration contains fields unsupported by the TC 8.0.2 decoders.";
      }
      {
        # TC polls at 97% of its configured intervals.
        assertion =
          cfg.httpTimeoutMs * 100 < 97 * min cfg.healthPollingIntervalMs cfg.statPollingIntervalMs
          && cfg.healthConnectionTimeoutMs <= cfg.httpTimeoutMs;
        message = "Traffic Monitor HTTP timeout must fit its health/stat interval and bound its per-cache timeout.";
      }
    ];
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
    environment.etc."traffic_monitor/traffic_ops.cfg".source = opsConfigFile;
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
          ${opsConfigFile} > ${runtimeOpsConfig}
        chown trafficmonitor:trafficmonitor ${runtimeOpsConfig}
        chmod 0600 ${runtimeOpsConfig}
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
            -opsCfg ${runtimeOpsConfig} \
            -config ${tmConfigFile}
        '';
      };
      path = [ pkgs.nettools ];
    };
  };
}
