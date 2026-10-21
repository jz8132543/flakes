{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.atc.ops;
  domain = config.networking.domain;

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

  passwordFilePath =
    if cfg.syncPasswordFile != null then
      cfg.syncPasswordFile
    else
      config.sops.secrets."atc/ops_password".path;

  initScript = pkgs.writeShellScript "traffic-ops-db-init" ''
    set -euo pipefail

    echo "Waiting for PostgreSQL at ${cfg.dbHost}:${toString cfg.dbPort}..."
    for i in $(seq 1 30); do
      if ${pkgs.postgresql}/bin/pg_isready -h ${cfg.dbHost} -p ${toString cfg.dbPort} -U ${cfg.dbUser} -d ${cfg.dbName} >/dev/null 2>&1; then
        echo "PostgreSQL is ready."
        break
      fi
      sleep 2
    done

    PASSWORD=""
    if [ -f "${toString passwordFilePath}" ]; then
      PASSWORD="$(cat "${toString passwordFilePath}" | tr -d '\r\n')"
    fi
    if [ -z "$PASSWORD" ]; then
      PASSWORD="sync-password-placeholder"
    fi

    echo "Provisioning Traffic Ops schema seeds, profile templates, and sync credentials..."
    ${pkgs.postgresql}/bin/psql -h ${cfg.dbHost} -p ${toString cfg.dbPort} -U ${cfg.dbUser} -d ${cfg.dbName} <<EOF || true
    CREATE EXTENSION IF NOT EXISTS pgcrypto;

    -- Ensure CDN
    INSERT INTO cdn (name, domain_name) 
    VALUES ('dora-cdn', '${domain}') 
    ON CONFLICT (name) DO NOTHING;

    -- Ensure Profile Type exists
    INSERT INTO type (name, description, use_in_table)
    VALUES ('ATS_PROFILE', 'Profile for Apache Traffic Server', 'profile')
    ON CONFLICT (name) DO NOTHING;

    -- Ensure Profile EDGE_ATS_GLOBAL
    INSERT INTO profile (name, description, type, cdn)
    SELECT 'EDGE_ATS_GLOBAL', 'Global Baseline Profile for Edge ATS Nodes', t.id, c.id
    FROM type t, cdn c
    WHERE t.name = 'ATS_PROFILE' AND c.name = 'dora-cdn'
    ON CONFLICT (name) DO NOTHING;

    -- Baseline records.config parameters for EDGE_ATS_GLOBAL
    DO \$\$
    DECLARE
      pid INT;
      param_id INT;
      rec RECORD;
    BEGIN
      SELECT id INTO pid FROM profile WHERE name = 'EDGE_ATS_GLOBAL';
      IF pid IS NOT NULL THEN
        FOR rec IN SELECT * FROM (VALUES
          ('proxy.config.http.cache.required_headers', 'records.config', '0'),
          ('proxy.config.http.cache.cache_responses_to_cookies', 'records.config', '1'),
          ('proxy.config.exec_thread.autoconfig.enabled', 'records.config', '1'),
          ('proxy.config.log.logging_enabled', 'records.config', '3'),
          ('proxy.config.ram_cache.size', 'records.config', '268435456'),
          ('proxy.config.cache.ram_cache.algorithm', 'records.config', '1'),
          ('proxy.config.net.connections_throttle', 'records.config', '10000'),
          ('proxy.config.http.server_ports', 'records.config', '80 80:ipv6 443:ssl 443:ssl:ipv6')
        ) AS t(pname, pfile, pval)
        LOOP
          INSERT INTO parameter (name, config_file, value)
          VALUES (rec.pname, rec.pfile, rec.pval)
          ON CONFLICT (name, config_file, value) DO UPDATE SET value = EXCLUDED.value
          RETURNING id INTO param_id;

          IF param_id IS NULL THEN
            SELECT id INTO param_id FROM parameter WHERE name = rec.pname AND config_file = rec.pfile AND value = rec.pval;
          END IF;

          INSERT INTO profile_parameter (profile, parameter)
          VALUES (pid, param_id)
          ON CONFLICT DO NOTHING;
        END LOOP;
      END IF;
    END \$\$;

    -- Ensure Role read-only exists
    INSERT INTO role (name, description, priv_level)
    VALUES ('read-only', 'Read-Only User for t3c edge synchronization', 10)
    ON CONFLICT (name) DO NOTHING;

    -- Ensure t3c-sync User exists with bcrypt password
    INSERT INTO tm_user (username, role, local_passwd, confirm_local_passwd, email, full_name)
    SELECT '${cfg.syncUser}', r.id, crypt('$PASSWORD', gen_salt('bf', 10)), crypt('$PASSWORD', gen_salt('bf', 10)), '${cfg.syncUser}@${domain}', 'T3C Edge Synchronizer'
    FROM role r
    WHERE r.name = 'read-only' OR r.priv_level = 10
    LIMIT 1
    ON CONFLICT (username) DO UPDATE
    SET local_passwd = crypt('$PASSWORD', gen_salt('bf', 10)),
        confirm_local_passwd = crypt('$PASSWORD', gen_salt('bf', 10));

    EOF
    echo "Traffic Ops initialization completed successfully."
  '';
in
{
  options.services.atc.ops = {
    enable = mkEnableOption "Apache Traffic Control Traffic Ops (Golang API)";

    listenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Address to bind Traffic Ops API. Use 0.0.0.0 for access across internal, overlay, and local interfaces.";
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

    syncUser = mkOption {
      type = types.str;
      default = "t3c-sync";
      description = "Read-only Traffic Ops API username for t3c edge nodes synchronization.";
    };

    syncPasswordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing password for the syncUser (defaults to config.sops.secrets.\"atc/ops_password\".path).";
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

    # 1. 自动确保数据库和用户存在（当使用本机 PostgreSQL 时）
    services.postgresql = mkIf (cfg.dbHost == "127.0.0.1" || cfg.dbHost == "localhost") {
      ensureDatabases = [ cfg.dbName ];
      ensureUsers = [
        {
          name = cfg.dbUser;
          ensureDBOwnership = true;
        }
      ];
    };

    # 2. 凭据权限配置
    sops.secrets."atc/ops_password" = mkIf (cfg.syncPasswordFile == null) {
      owner = mkDefault "trafficops";
      group = mkDefault "trafficops";
      mode = mkDefault "0440";
    };

    # 3. 数据库初始化服务（初始化只读同步账户与 EDGE_ATS_GLOBAL Profile 模板）
    systemd.services.traffic-ops-init = {
      description = "Initialize Apache Traffic Ops database seeds, templates, and sync credentials";
      after = [
        "network-online.target"
      ]
      ++ optional (cfg.dbHost == "127.0.0.1" || cfg.dbHost == "localhost") "postgresql.service";
      wants = [ "network-online.target" ];
      before = [ "traffic-ops.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "trafficops";
        Group = "trafficops";
        ExecStart = "${initScript}";
      };
    };

    # 4. Traffic Ops 主服务
    systemd.services.traffic-ops = {
      description = "Apache Traffic Control Traffic Ops API";
      after = [
        "network-online.target"
        "traffic-ops-init.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "trafficops";
        Group = "trafficops";
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

    # 5. 网络可达性：Traefik 统一配置 HTTPS 反代入口与防火墙端口放行
    services.traefik.proxies.traffic-ops = mkIf (config.services.traefik.enable or false) {
      rule = "Host(`ops.${domain}`)";
      target = "http://127.0.0.1:${toString cfg.port}";
      entryPoints = [ "https" ];
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
