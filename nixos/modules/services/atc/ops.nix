{
  config,
  lib,
  pkgs,
  self ? null,
  ...
}:
with lib;
let
  cfg = config.services.atc.ops;
  domain = config.networking.domain;
  tlsDirectory = "/var/lib/traffic_ops/tls";
  tlsCertificate = "${tlsDirectory}/traffic-ops.crt";
  tlsKey = "${tlsDirectory}/traffic-ops.key";

  cdnData = (builtins.fromJSON (builtins.readFile ../../../../lib/data/data.json)).cdn;
  controlNodes = cdnData.controlNodes or [ ];
  edgeNodes = cdnData.edgeNodes or [ ];
  servicesMap = cdnData.services or { };

  # ── 版本指纹元数据 (用于多控制节点版本仲裁与防倒退比对) ───────────────────
  versionInfo = {
    host = config.networking.hostName;
    epoch = self.lastModified or (0);
    lastModifiedDate = self.lastModifiedDate or "19700101000000";
    gitRev = self.rev or (self.dirtyRev or "dirty");
    shortRev = if self ? rev then builtins.substring 0 8 self.rev else "dirty";
    nixosVersion = config.system.nixos.version;
    label = config.system.nixos.label;
    fingerprint = "${toString (self.lastModified or 0)}-${
      if self ? rev then builtins.substring 0 8 self.rev else "dirty"
    }-${config.system.nixos.label}";
  };
  versionJson = pkgs.writeText "atc-version.json" (builtins.toJSON versionInfo);

  # Reuse the existing SOPS-managed credential by default. This keeps the
  # deployment self-contained; a separate secret can be introduced later.
  cookieSecretPath = config.sops.secrets."atc/ops_password".path;

  cdnConfigFile = pkgs.writeText "cdn.conf" (
    builtins.toJSON {
      # Filled from SOPS at service start. Do not put signing material in the
      # Nix store, since this file is world-readable through the system closure.
      secrets = [ ];
      traffic_ops_golang = {
        cert = tlsCertificate;
        key = tlsKey;
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
        # Empty disables Traffic Vault. Any non-empty value selects a backend
        # and requires a matching traffic_vault_config object.
        traffic_vault_backend = "";
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

  scryptTool = pkgs.python3.withPackages (ps: [ ps.cryptography ]);
  scryptScript = pkgs.writeText "traffic-ops-scrypt.py" ''
    import base64
    import os
    import sys
    from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

    password = sys.stdin.buffer.read().rstrip(bytes((13, 10)))
    salt = os.urandom(64)
    key = Scrypt(salt=salt, length=64, n=16384, r=8, p=1).derive(password)
    print("SCRYPT:16384:8:1:%s:%s" % (
        base64.b64encode(salt).decode(),
        base64.b64encode(key).decode(),
    ))
  '';

  initScript = pkgs.writeShellScript "traffic-ops-db-init" ''
        set -euo pipefail

        echo "Waiting for PostgreSQL at ${cfg.dbHost}:${toString cfg.dbPort}..."
        for i in $(seq 1 30); do
          if ${pkgs.postgresql}/bin/pg_isready -h ${cfg.dbHost} -p ${toString cfg.dbPort} -U postgres -d postgres >/dev/null 2>&1; then
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

        # Ensure database and owner role exist. PostgreSQL local authentication is
        # trusted on the center node, so this does not put a DB password in Nix.
        if ! ${pkgs.postgresql}/bin/psql -h ${cfg.dbHost} -p ${toString cfg.dbPort} -U postgres -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '${cfg.dbName}'" | grep -q 1; then
          ${pkgs.postgresql}/bin/psql -h ${cfg.dbHost} -p ${toString cfg.dbPort} -U postgres -d postgres -v ON_ERROR_STOP=1 <<SQL
        DO ''$''$
        BEGIN
          IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${cfg.dbUser}') THEN
            CREATE ROLE ${cfg.dbUser} LOGIN;
          END IF;
        END
        ''$''$;
        CREATE DATABASE ${cfg.dbName} OWNER ${cfg.dbUser};
    SQL
        fi

        # Initialize tables and seed data if not yet populated
        HAS_TABLES=$(${pkgs.postgresql}/bin/psql -h ${cfg.dbHost} -p ${toString cfg.dbPort} -U ${cfg.dbUser} -d ${cfg.dbName} -Atc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" | tr -d '[:space:]')
        if [ -z "$HAS_TABLES" ]; then HAS_TABLES=0; fi
        if [ "$HAS_TABLES" -le 1 ]; then
          echo "Populating Traffic Ops base tables and seed data..."
          ${pkgs.postgresql}/bin/psql -v ON_ERROR_STOP=1 -h ${cfg.dbHost} -p ${toString cfg.dbPort} -U ${cfg.dbUser} -d ${cfg.dbName} -f ${cfg.package}/share/traffic_ops/db/create_tables.sql
          ${pkgs.postgresql}/bin/psql -v ON_ERROR_STOP=1 -h ${cfg.dbHost} -p ${toString cfg.dbPort} -U ${cfg.dbUser} -d ${cfg.dbName} -f ${cfg.package}/share/traffic_ops/db/seeds.sql
        fi

        # Apply the schema additions required by the Traffic Ops 8.0 binary.
        # The upstream release migrations are not all idempotent, so do not replay
        # every .up.sql file on each boot. These ALTERs are safe on every start.
        ${pkgs.postgresql}/bin/psql -v ON_ERROR_STOP=1 -h ${cfg.dbHost} -p ${toString cfg.dbPort} -U postgres -d ${cfg.dbName} <<MIGRATIONS
        ALTER TABLE public.cdn ADD COLUMN IF NOT EXISTS ttl_override BIGINT DEFAULT NULL;
        ALTER TABLE public.deliveryservice ADD COLUMN IF NOT EXISTS regional BOOLEAN NOT NULL DEFAULT FALSE;
        ALTER TABLE public.deliveryservice ADD COLUMN IF NOT EXISTS required_capabilities TEXT[];
        ALTER TABLE public.server ADD COLUMN IF NOT EXISTS config_update_failed BOOLEAN NOT NULL DEFAULT FALSE;
        ALTER TABLE public.server ADD COLUMN IF NOT EXISTS revalidate_update_failed BOOLEAN NOT NULL DEFAULT FALSE;
        ALTER TABLE public.server_capability ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT ' ';
    MIGRATIONS

        PASSWORD_HASH="$(${scryptTool}/bin/python ${scryptScript} < "${passwordFilePath}")"

        ${pkgs.postgresql}/bin/psql -v ON_ERROR_STOP=1 -v password_hash="$PASSWORD_HASH" -h ${cfg.dbHost} -p ${toString cfg.dbPort} -U ${cfg.dbUser} -d ${cfg.dbName} <<'EOF'
        CREATE EXTENSION IF NOT EXISTS pgcrypto;

        -- Ensure CDN
        INSERT INTO cdn (name, domain_name)
        VALUES ('dora-cdn', '${domain}')
        ON CONFLICT (name) DO NOTHING;

        -- Ensure Profile Type exists
        -- Ensure Profile EDGE_ATS_GLOBAL
        INSERT INTO profile (name, description, type, cdn)
        SELECT 'EDGE_ATS_GLOBAL', 'Global Baseline Profile for Edge ATS Nodes', 'ATS_PROFILE'::profile_type, c.id
        FROM cdn c
        WHERE c.name = 'dora-cdn'
        ON CONFLICT (name) DO NOTHING;

        -- Ensure Profile RASCAL_GLOBAL exists before assigning parameters
        INSERT INTO profile (name, description, type, cdn)
        SELECT 'RASCAL_GLOBAL', 'Traffic Monitor baseline profile', 'ATS_PROFILE'::profile_type, c.id
        FROM cdn c WHERE c.name = 'dora-cdn'
        ON CONFLICT (name) DO NOTHING;

        INSERT INTO parameter (name, config_file, value) VALUES
          ('peers.polling.interval', 'rascal-config.txt', '3000'),
          ('health.polling.interval', 'rascal-config.txt', '20000'),
          ('stat.polling.interval', 'rascal-config.txt', '60000'),
          ('health.polling.url', 'rascal.properties', 'http://''${hostname}/_astats'),
          ('health.polling.format', 'rascal.properties', 'astats'),
          ('health.polling.type', 'rascal.properties', 'HTTP'),
          ('health.connection.timeout', 'rascal.properties', '5000')
        ON CONFLICT (name, config_file, value) DO NOTHING;

        INSERT INTO profile_parameter (profile, parameter)
        SELECT p.id, pr.id FROM profile p CROSS JOIN parameter pr
        WHERE p.name = 'RASCAL_GLOBAL' AND pr.config_file = 'rascal-config.txt'
        ON CONFLICT DO NOTHING;

        INSERT INTO profile_parameter (profile, parameter)
        SELECT p.id, pr.id FROM profile p CROSS JOIN parameter pr
        WHERE p.name = 'EDGE_ATS_GLOBAL' AND pr.config_file = 'rascal.properties'
        ON CONFLICT DO NOTHING;

        -- Minimal topology required by Traffic Monitor/t3c discovery.
        INSERT INTO division (name) VALUES ('Global') ON CONFLICT (name) DO NOTHING;
        INSERT INTO region (name, division)
        SELECT 'ALL', d.id FROM division d WHERE d.name = 'Global'
        ON CONFLICT (name) DO NOTHING;
        INSERT INTO phys_location (name, short_name, address, city, state, zip, region)
        SELECT 'Global Edge', 'global-edge', 'N/A', 'N/A', 'N/A', 'N/A', r.id
        FROM region r WHERE r.name = 'ALL'
        ON CONFLICT (name) DO NOTHING;

        INSERT INTO cachegroup (name, short_name, type)
        SELECT 'EDGE_DEFAULT', 'edge-default', t.id
        FROM type t WHERE t.name = 'EDGE'
        ON CONFLICT (name) DO NOTHING;

        INSERT INTO coordinate (name, latitude, longitude)
        VALUES ('global-edge-coordinate', 0.0, 0.0)
        ON CONFLICT (name) DO NOTHING;
        UPDATE cachegroup SET coordinate = (SELECT id FROM coordinate WHERE name = 'global-edge-coordinate')
        WHERE name = 'EDGE_DEFAULT' AND coordinate IS NULL;

        -- ── 声明式注册所有加速业务 (Delivery Services, Origins, Regexes) ──
        ${concatMapStringsSep "\n" (
          svcName:
          let
            originHost = servicesMap.${svcName};
          in
          ''
            INSERT INTO deliveryservice (
              xml_id, active, dscp, type, profile, cdn_id, display_name, tenant_id,
              routing_name, protocol, ipv6_routing_enabled, edge_header_rewrite
            )
            SELECT '${svcName}', 'ACTIVE'::ds_active_state, 0, t.id, p.id, c.id, '${svcName} service', tn.id,
              'edge', 2, true, 'cond %{SEND_REQUEST_HDR_HOOK}' || chr(10) || 'set-header Host "${svcName}.${domain}"'
            FROM type t, profile p, cdn c, tenant tn
            WHERE t.name = 'HTTP' AND p.name = 'EDGE_ATS_GLOBAL' AND c.name = 'dora-cdn' AND tn.name = 'root'
            ON CONFLICT (xml_id) DO UPDATE SET active = 'ACTIVE'::ds_active_state, protocol = 2,
              edge_header_rewrite = EXCLUDED.edge_header_rewrite;

            INSERT INTO origin (name, fqdn, protocol, is_primary, port, deliveryservice, tenant)
            SELECT '${svcName}-origin', '${originHost}.${domain}', 'https'::origin_protocol, true, 443, ds.id, tn.id
            FROM deliveryservice ds, tenant tn
            WHERE ds.xml_id = '${svcName}' AND tn.name = 'root'
            ON CONFLICT (name) DO UPDATE SET fqdn = EXCLUDED.fqdn;

            INSERT INTO regex (pattern, type)
            SELECT '${svcName}.${domain}', t.id FROM type t
            WHERE t.name = 'HOST_REGEXP'
              AND NOT EXISTS (SELECT 1 FROM regex r WHERE r.pattern = '${svcName}.${domain}');

            INSERT INTO regex (pattern, type)
            SELECT '${svcName}.cdn.${domain}', t.id FROM type t
            WHERE t.name = 'HOST_REGEXP'
              AND NOT EXISTS (SELECT 1 FROM regex r WHERE r.pattern = '${svcName}.cdn.${domain}');

            INSERT INTO deliveryservice_regex (deliveryservice, regex, set_number)
            SELECT ds.id, r.id, 0 FROM deliveryservice ds, regex r
            WHERE ds.xml_id = '${svcName}' AND r.pattern = '${svcName}.${domain}'
              AND NOT EXISTS (SELECT 1 FROM deliveryservice_regex dr WHERE dr.deliveryservice = ds.id AND dr.regex = r.id);

            INSERT INTO deliveryservice_regex (deliveryservice, regex, set_number)
            SELECT ds.id, r.id, 1 FROM deliveryservice ds, regex r
            WHERE ds.xml_id = '${svcName}' AND r.pattern = '${svcName}.cdn.${domain}'
              AND NOT EXISTS (SELECT 1 FROM deliveryservice_regex dr WHERE dr.deliveryservice = ds.id AND dr.regex = r.id);
          ''
        ) (attrNames servicesMap)}

        DO ''$''$
        DECLARE
          cdn_id_value BIGINT;
          profile_id_value BIGINT;
          location_id_value BIGINT;
          cachegroup_id_value BIGINT;
          edge_type BIGINT;
          online_status BIGINT;
          reported_status BIGINT;
          host RECORD;
          existing_id BIGINT;
        BEGIN
          SELECT id INTO cdn_id_value FROM cdn WHERE name = 'dora-cdn';
          SELECT id INTO profile_id_value FROM profile WHERE name = 'EDGE_ATS_GLOBAL';
          SELECT id INTO location_id_value FROM phys_location WHERE name = 'Global Edge';
          SELECT id INTO cachegroup_id_value FROM cachegroup WHERE name = 'EDGE_DEFAULT';
          SELECT id INTO edge_type FROM type WHERE name = 'EDGE';
          SELECT id INTO online_status FROM status WHERE name = 'ONLINE';
          SELECT id INTO reported_status FROM status WHERE name = 'REPORTED';

          -- ── 动态注册声明的所有边缘节点 (cdn.edgeNodes) ─────────────────
          FOR host IN SELECT * FROM (VALUES
            ${concatMapStringsSep ",\n            " (n: "('${n.name}', '${n.ipv4}')") edgeNodes}
          ) AS h(host_name, mgmt_ip)
          LOOP
            SELECT id INTO existing_id FROM server WHERE host_name = host.host_name;
            IF existing_id IS NULL THEN
              INSERT INTO server (
                host_name, domain_name, tcp_port, phys_location, cachegroup,
                type, status, profile, cdn_id, mgmt_ip_address, https_port
              ) VALUES (
                host.host_name, '${domain}', 80, location_id_value, cachegroup_id_value,
                edge_type, reported_status, profile_id_value, cdn_id_value,
                host.mgmt_ip, 443
              );
            ELSE
              UPDATE server SET
                domain_name = '${domain}',
                cachegroup = cachegroup_id_value,
                type = edge_type,
                status = reported_status,
                profile = profile_id_value,
                cdn_id = cdn_id_value,
                mgmt_ip_address = host.mgmt_ip,
                https_port = 443,
                config_update_time = now()
              WHERE id = existing_id;
            END IF;

            INSERT INTO server_profile (server, profile_name, priority)
            SELECT s.id, 'EDGE_ATS_GLOBAL', 1 FROM server s
            WHERE s.host_name = host.host_name
              AND NOT EXISTS (SELECT 1 FROM server_profile sp WHERE sp.server = s.id AND sp.profile_name = 'EDGE_ATS_GLOBAL');
          END LOOP;

          -- ── 动态注册控制节点的 Traffic Monitor 实例 ────────────────────
          ${concatMapStringsSep "\n" (ctrl: ''
            INSERT INTO server (
              host_name, domain_name, tcp_port, phys_location, cachegroup,
              type, status, profile, cdn_id, mgmt_ip_address, https_port
            )
            SELECT '${ctrl.name}', '${domain}', 8087, location_id_value, cachegroup_id_value,
              (SELECT id FROM type WHERE name = 'RASCAL'), online_status,
              (SELECT id FROM profile WHERE name = 'RASCAL_GLOBAL'), cdn_id_value,
              '127.0.0.1', 8087
            WHERE NOT EXISTS (SELECT 1 FROM server WHERE host_name = '${ctrl.name}' AND type = (SELECT id FROM type WHERE name = 'RASCAL'));

            INSERT INTO server_profile (server, profile_name, priority)
            SELECT s.id, 'RASCAL_GLOBAL', 1 FROM server s
            WHERE s.host_name = '${ctrl.name}' AND s.type = (SELECT id FROM type WHERE name = 'RASCAL')
              AND NOT EXISTS (SELECT 1 FROM server_profile sp WHERE sp.server = s.id AND sp.profile_name = 'RASCAL_GLOBAL');

            INSERT INTO interface (name, monitor, mtu, server)
            SELECT 'eth0', true, 1500, s.id FROM server s
            WHERE s.host_name = '${ctrl.name}' AND s.type = (SELECT id FROM type WHERE name = 'RASCAL')
              AND NOT EXISTS (SELECT 1 FROM interface i WHERE i.name = 'eth0' AND i.server = s.id);

            INSERT INTO ip_address (address, interface, server, service_address)
            SELECT '127.0.0.1'::inet, 'eth0', s.id, true
            FROM server s WHERE s.host_name = '${ctrl.name}' AND s.type = (SELECT id FROM type WHERE name = 'RASCAL')
              AND NOT EXISTS (SELECT 1 FROM ip_address ip WHERE ip.address = '127.0.0.1'::inet AND ip.server = s.id);
          '') controlNodes}

          -- ── 为所有边缘节点注册网卡与 IP ───────────────────────────────
          ${concatMapStringsSep "\n" (node: ''
            INSERT INTO interface (name, monitor, mtu, server)
            SELECT 'eth0', true, 1500, s.id FROM server s
            WHERE s.host_name = '${node.name}'
              AND NOT EXISTS (SELECT 1 FROM interface i WHERE i.name = 'eth0' AND i.server = s.id);

            INSERT INTO ip_address (address, interface, server, service_address)
            SELECT '${node.ipv4}'::inet, 'eth0', s.id, true
            FROM server s WHERE s.host_name = '${node.name}'
              AND NOT EXISTS (SELECT 1 FROM ip_address ip WHERE ip.address = '${node.ipv4}'::inet AND ip.server = s.id);

            ${optionalString ((node.ipv6 or null) != null) ''
              INSERT INTO ip_address (address, interface, server, service_address)
              SELECT '${node.ipv6}'::inet, 'eth0', s.id, false
              FROM server s WHERE s.host_name = '${node.name}'
                AND NOT EXISTS (SELECT 1 FROM ip_address ip WHERE ip.address = '${node.ipv6}'::inet AND ip.server = s.id);
            ''}
          '') edgeNodes}

          -- ── 绑定所有 Delivery Services 到所有边缘缓存节点 ────────────
          ${concatMapStringsSep "\n" (
            svcName:
            concatMapStringsSep "\n" (node: ''
              INSERT INTO deliveryservice_server (deliveryservice, server)
              SELECT ds.id, s.id FROM deliveryservice ds, server s
              WHERE ds.xml_id = '${svcName}' AND s.host_name = '${node.name}'
                AND NOT EXISTS (SELECT 1 FROM deliveryservice_server dss WHERE dss.deliveryservice = ds.id AND dss.server = s.id);
            '') edgeNodes
          ) (attrNames servicesMap)}
        END ''$''$;

        -- Baseline records.config parameters for EDGE_ATS_GLOBAL
        DO ''$''$
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
              ('proxy.config.http.server_ports', 'records.config', '80 80:ipv6 443:ssl 443:ssl:ipv6'),
              ('proxy.config.url_remap.pristine_host_hdr', 'records.config', '1'),
              ('location', 'set_dscp_0.config', '/var/lib/trafficserver/etc/dscp')
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
        END ''$''$;

        -- Ensure Role read-only exists
        INSERT INTO role (name, description, priv_level)
        VALUES ('read-only', 'Read-Only User for t3c edge synchronization', 10)
        ON CONFLICT (name) DO NOTHING;

        -- Ensure t3c-sync User exists with operations role (required for snapshots & sync)
        INSERT INTO tm_user (username, role, local_passwd, confirm_local_passwd, email, full_name, tenant_id)
        SELECT '${cfg.syncUser}', r.id, :'password_hash', :'password_hash', '${cfg.syncUser}@${domain}', 'T3C Edge Synchronizer', t.id
        FROM role r
        CROSS JOIN tenant t
        WHERE r.name = 'operations' AND t.name = 'root'
        LIMIT 1
        ON CONFLICT (username) DO UPDATE
        SET role = EXCLUDED.role,
            local_passwd = EXCLUDED.local_passwd,
            confirm_local_passwd = EXCLUDED.confirm_local_passwd,
            tenant_id = EXCLUDED.tenant_id,
            email = EXCLUDED.email;

        -- Record control-plane version fingerprint for edge discovery and anti-rollback
        INSERT INTO parameter (name, config_file, value) VALUES
          ('cdn.version.epoch', 'global', '${toString versionInfo.epoch}'),
          ('cdn.version.git_rev', 'global', '${versionInfo.gitRev}'),
          ('cdn.version.nixos_version', 'global', '${versionInfo.nixosVersion}'),
          ('cdn.version.fingerprint', 'global', '${versionInfo.fingerprint}')
        ON CONFLICT (name, config_file, value) DO UPDATE SET value = EXCLUDED.value;

    EOF

        echo "Triggering initial Traffic Ops CRConfig Snapshot for dora-cdn..."
        PASS="$(cat ${passwordFilePath} | tr -d '\r\n')"
        COOKIE_JAR="$(mktemp)"
        curl -k -s -c "$COOKIE_JAR" -H "Content-Type: application/json" \
          -d "{\"u\":\"${cfg.syncUser}\",\"p\":\"$PASS\"}" \
          https://127.0.0.1:${toString cfg.port}/api/5.0/user/login > /dev/null || true
        curl -k -s -X PUT -b "$COOKIE_JAR" \
          "https://127.0.0.1:${toString cfg.port}/api/5.0/snapshot?cdn=dora-cdn" > /dev/null || true
        rm -f "$COOKIE_JAR"

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
      default = 8084;
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
      "d /var/lib/traffic_ops 0750 trafficops trafficops -"
    ];

    # The final cdn.conf is rendered in preStart with the SOPS secret injected.
    environment.etc."traffic_ops/cdn.conf".enable = false;
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
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        # Migrations alter tables created by the postgres owner. The script
        # connects as PostgreSQL's local postgres role and must not run as the
        # unprivileged daemon user.
        User = "root";
        Group = "root";
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
      requires = [ "traffic-ops-init.service" ];
      wantedBy = [ "multi-user.target" ];

      preStart = ''
        if [ ! -s ${cookieSecretPath} ]; then
          echo "Traffic Ops signing secret is missing or empty" >&2
          exit 1
        fi

        mkdir -p /var/lib/traffic_ops/app/conf
        cp -f ${cfg.package}/share/traffic_ops/app/conf/invalid_passwords.txt \
          /var/lib/traffic_ops/app/conf/invalid_passwords.txt
        chown -R trafficops:trafficops /var/lib/traffic_ops

        mkdir -p ${tlsDirectory}
        if [ ! -s ${tlsCertificate} ] || [ ! -s ${tlsKey} ]; then
          ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:2048 -nodes \
            -keyout ${tlsKey} -out ${tlsCertificate} -days 3650 \
            -subj "/CN=ops.${domain}" \
            -addext "subjectAltName=DNS:ops.${domain},DNS:localhost,IP:127.0.0.1"
        fi
        chown -R trafficops:trafficops ${tlsDirectory}
        chmod 0644 ${tlsCertificate}
        chmod 0600 ${tlsKey}

        ${pkgs.jq}/bin/jq --rawfile secret ${cookieSecretPath} \
          '.secrets = [($secret | rtrimstr("\n") | rtrimstr("\r"))]' \
          ${cdnConfigFile} > /etc/traffic_ops/cdn.conf
        chown trafficops:trafficops /etc/traffic_ops/cdn.conf
        chmod 0600 /etc/traffic_ops/cdn.conf
      '';

      serviceConfig = {
        Type = "simple";
        WorkingDirectory = "/var/lib/traffic_ops";
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

    # 5. 控制平面版本服务 (提供 /version.json 与 /api/version.json 供边缘节点比对选优)
    systemd.services.traffic-ops-version = {
      description = "Traffic Ops Version Metadata Service";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        ExecStart = "${pkgs.python3}/bin/python3 -m http.server 8092 --bind 127.0.0.1 --directory ${
          pkgs.runCommand "atc-version-dir" { } ''
            mkdir -p $out/api
            cp ${versionJson} $out/version.json
            cp ${versionJson} $out/api/version.json
          ''
        }";
        Restart = "always";
      };
    };

    # 6. 网络可达性：Traefik 统一配置 HTTPS 反代入口与防火墙端口放行
    services.traefik.proxies.traffic-ops-version = mkIf (config.services.traefik.enable or false) {
      rule = "Host(`ops.${domain}`) && (Path(`/version.json`) || Path(`/api/version.json`))";
      target = "http://127.0.0.1:8092";
      entryPoints = [ "https" ];
      priority = 2000;
    };

    services.traefik.proxies.traffic-ops = mkIf (config.services.traefik.enable or false) {
      rule = "Host(`ops.${domain}`)";
      target = "https://127.0.0.1:${toString cfg.port}";
      entryPoints = [ "https" ];
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
