{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.atc.ops;

  cdnConfigFile = pkgs.writeText "cdn.conf" (
    builtins.toJSON {
      traffic_ops_golang = {
        port = toString cfg.port;
        listen = [ "${cfg.listenAddress}:${toString cfg.port}" ];
        proxy_keep_alive_time = 300;
        read_timeout = 60;
        write_timeout = 60;
        idle_timeout = 300;
        insecure = true;
        log_location_error = "stderr";
        log_location_warning = "stderr";
        log_location_info = "null";
        log_location_debug = "null";
        log_location_event = "stdout";
        db_query_timeout_seconds = 30;
        traffic_vault_backend = "disabled";
      };
      cors = {
        access_control_allow_origin = "*";
      };
    }
  );

  dbConfigFile = pkgs.writeText "database.conf" (
    builtins.toJSON {
      description = "Traffic Ops PostgreSQL connection";
      dbname = cfg.dbName;
      hostname = cfg.dbHost;
      user = cfg.dbUser;
      password = "";
      port = toString cfg.dbPort;
      ssl = false;
      type = "Pg";
      max_connections = 20;
    }
  );
in
{
  options.services.atc.ops = {
    enable = mkEnableOption "Apache Traffic Control Traffic Ops (Golang API)";

    listenAddress = mkOption {
      type = types.str;
      default = "100.64.0.1";
      description = "Address to bind Traffic Ops API (strictly Tailscale overlay IP)";
    };

    port = mkOption {
      type = types.port;
      default = 443;
      description = "Port to listen on Tailscale overlay";
    };

    dbHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "PostgreSQL host";
    };

    dbPort = mkOption {
      type = types.port;
      default = 5432;
      description = "PostgreSQL port";
    };

    dbName = mkOption {
      type = types.str;
      default = "traffic_ops";
      description = "PostgreSQL database name";
    };

    dbUser = mkOption {
      type = types.str;
      default = "traffic_ops";
      description = "PostgreSQL database username";
    };

    dbPasswordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to PostgreSQL password file";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.trafficcontrol;
      description = "Package providing traffic_ops_golang binary";
    };
  };

  config = mkIf cfg.enable {
    users.users.trafficops = {
      isSystemUser = true;
      group = "trafficops";
      description = "Apache Traffic Ops daemon user";
    };
    users.groups.trafficops = { };

    systemd.tmpfiles.rules = [
      "d /etc/traffic_ops 0750 trafficops trafficops -"
      "d /var/log/traffic_ops 0750 trafficops trafficops -"
    ];

    environment.etc."traffic_ops/cdn.conf".source = cdnConfigFile;
    environment.etc."traffic_ops/database.conf".source = dbConfigFile;

    # 依赖并连接 PostgreSQL 服务
    systemd.services.traffic-ops = {
      description = "Apache Traffic Control Traffic Ops API";
      after = [
        "network-online.target"
        "postgresql.service"
      ];
      wants = [
        "network-online.target"
        "postgresql.service"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "trafficops";
        Group = "trafficops";
        Restart = "always";
        RestartSec = "10s";

        # 仅绑定 Tailscale 内网地址，绝不向公网暴露
        ExecStart = ''
          ${cfg.package}/bin/traffic_ops_golang \
            -cfg /etc/traffic_ops/cdn.conf \
            -dbcfg /etc/traffic_ops/database.conf
        '';
      };
    };
  };
}
