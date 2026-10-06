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
        # Running over plain HTTP on the public interface, TLS is terminated
        # by Traefik (or handled by the origin's own TLS stack).
        # No insecure flag needed — we are the origin server.
        log_location_error = "stderr";
        log_location_warning = "stderr";
        log_location_info = "null";
        log_location_debug = "null";
        log_location_event = "stdout";
        db_query_timeout_seconds = 30;
        traffic_vault_backend = "disabled";
      };
    }
  );

  dbConfigFile = pkgs.writeText "database.conf" (
    builtins.toJSON {
      description = "Traffic Ops PostgreSQL connection";
      dbname = cfg.dbName;
      hostname = cfg.dbHost;
      user = cfg.dbUser;
      # Password-less peer/trust authentication assumed (PostgreSQL pg_hba.conf).
      # password field intentionally omitted.
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
      default = "0.0.0.0";
      description = "Address to bind Traffic Ops API. Use 0.0.0.0 for public access (Traefik will restrict exposure).";
    };

    port = mkOption {
      type = types.port;
      default = 8088;
      description = "Port to listen on (plain HTTP; Traefik terminates TLS externally).";
    };

    dbHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "PostgreSQL host.";
    };

    dbPort = mkOption {
      type = types.port;
      default = 5432;
      description = "PostgreSQL port.";
    };

    dbName = mkOption {
      type = types.str;
      default = "traffic_ops";
      description = "PostgreSQL database name.";
    };

    dbUser = mkOption {
      type = types.str;
      default = "traffic_ops";
      description = "PostgreSQL database username.";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.trafficcontrol;
      description = "Package providing traffic_ops_golang binary.";
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

    systemd.services.traffic-ops = {
      description = "Apache Traffic Control Traffic Ops API";
      # Do not declare postgresql.service as a dependency — the database may
      # be on a remote host. Instead rely on the Restart policy: if the DB
      # is not ready the process will exit and systemd will retry.
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "trafficops";
        Group = "trafficops";
        # Restart on any failure and keep retrying — this is the simplest way
        # to handle transient DB unavailability without over-engineering.
        Restart = "always";
        RestartSec = "10s";
        StartLimitIntervalSec = 0;
        MemoryMax = "512M";
        LimitNOFILE = 65536;

        ExecStart = ''
          ${cfg.package}/bin/traffic_ops_golang \
            -cfg /etc/traffic_ops/cdn.conf \
            -dbcfg /etc/traffic_ops/database.conf
        '';
      };
    };
  };
}
