# ─────────────────────────────────────────────────────────────────────────────
# services/ai/mcp/db-init.nix
#
# ContextForge PostgreSQL 初始化 oneshot service
#
# 与 Dify 的 db-init 同样的约束：
#   • 禁用 ensureDatabases / ensureUsers
#   • 手动创建用户（无密码，内网 trust）、数据库、授权、扩展
# ─────────────────────────────────────────────────────────────────────────────
{
  config,
  mcpConnVars,
  ...
}:
let
  inherit (mcpConnVars)
    pgHost
    pgPort
    mcpPgUser
    mcpPgDb
    ;

  psql = "${config.services.postgresql.package}/bin/psql";
in
{
  systemd.services.contextforge-db-init = {
    description = "Initialize ContextForge PostgreSQL user, database and extensions";

    after = [
      "postgresql.service"
      "postgresql-setup.service"
      "sops-install-secrets.service"
    ];
    requires = [
      "postgresql.service"
    ];
    before = [
      "podman-contextforge.service"
    ];

    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "postgres";
    };

    script = ''
      set -euo pipefail

      echo "[contextforge-db-init] Waiting for PostgreSQL..."
      for i in $(seq 1 30); do
        ${config.services.postgresql.package}/bin/pg_isready \
          -h ${pgHost} -p ${toString pgPort} -U postgres -q && break
        sleep 2
      done

      echo "[contextforge-db-init] Refreshing collation version for template databases..."
      ${psql} -h ${pgHost} -p ${toString pgPort} -U postgres \
        --set=ON_ERROR_STOP=1 \
        -c "ALTER DATABASE template1 REFRESH COLLATION VERSION;" || true
      ${psql} -h ${pgHost} -p ${toString pgPort} -U postgres \
        --set=ON_ERROR_STOP=1 \
        -c "ALTER DATABASE postgres REFRESH COLLATION VERSION;" || true

      echo "[contextforge-db-init] Creating role '${mcpPgUser}'..."
      ${psql} -h ${pgHost} -p ${toString pgPort} -U postgres \
        --set=ON_ERROR_STOP=1 \
        -c "DO \$\$
          BEGIN
            IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${mcpPgUser}') THEN
              CREATE ROLE ${mcpPgUser} LOGIN;
            END IF;
          END
        \$\$;"

      echo "[contextforge-db-init] Creating database '${mcpPgDb}' if not exists..."
      ${psql} -h ${pgHost} -p ${toString pgPort} -U postgres \
        --set=ON_ERROR_STOP=1 \
        -tAc "SELECT 1 FROM pg_database WHERE datname='${mcpPgDb}'" \
        | grep -q 1 || \
      ${psql} -h ${pgHost} -p ${toString pgPort} -U postgres \
        --set=ON_ERROR_STOP=1 \
        -c "CREATE DATABASE ${mcpPgDb} OWNER ${mcpPgUser};"

      echo "[contextforge-db-init] Granting privileges..."
      ${psql} -h ${pgHost} -p ${toString pgPort} -U postgres -d ${mcpPgDb} \
        --set=ON_ERROR_STOP=1 \
        -c "GRANT ALL PRIVILEGES ON DATABASE ${mcpPgDb} TO ${mcpPgUser};"

      echo "[contextforge-db-init] Enabling extensions..."
      ${psql} -h ${pgHost} -p ${toString pgPort} -U postgres -d ${mcpPgDb} \
        --set=ON_ERROR_STOP=1 \
        -c "
          CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";
          CREATE EXTENSION IF NOT EXISTS pg_trgm;
        "

      echo "[contextforge-db-init] Done."
    '';
  };
}
