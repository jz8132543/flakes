# ─────────────────────────────────────────────────────────────────────────────
# services/ai/dify/db-init.nix
#
# 数据库初始化 Systemd oneshot service
#
# 责任：
#   1. 创建 dify PostgreSQL 用户（密码为空，纯内网 trust 认证）
#   2. 创建 dify 数据库并授权
#   3. 启用必要 PG 扩展（vector、uuid-ossp）
#
# 约束：
#   • 绝对禁止使用 services.postgresql.ensureDatabases / ensureUsers
#   • pgHost/pgPort/difyPgUser/difyPgDb 从 difyConnVars 注入，不硬编码
#   • 必须在 PG 就绪后、OCI 容器启动前成功完成
# ─────────────────────────────────────────────────────────────────────────────
{
  config,
  difyConnVars,
  ...
}:
let
  inherit (difyConnVars)
    pgHost
    pgPort
    difyPgUser
    difyPgDb
    ;

  psql = "${config.services.postgresql.package}/bin/psql";
in
{
  systemd.services.dify-db-init = {
    description = "Initialize Dify PostgreSQL user, database and extensions";

    after = [
      "postgresql.service"
      "postgresql-setup.service"
      "sops-install-secrets.service"
    ];
    requires = [
      "postgresql.service"
    ];
    # 声明为其它 Dify 容器的前置依赖
    before = [
      "podman-dify-api.service"
      "podman-dify-worker.service"
      "podman-dify-web.service"
      "podman-dify-sandbox.service"
    ];

    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # 以 postgres 系统用户身份运行，可直接使用 peer/trust 认证
      User = "postgres";
    };

    script = ''
      set -euo pipefail

      echo "[dify-db-init] Waiting for PostgreSQL to be ready..."
      for i in $(seq 1 30); do
        ${config.services.postgresql.package}/bin/pg_isready \
          -h ${pgHost} -p ${toString pgPort} -U postgres -q && break
        sleep 2
      done

      echo "[dify-db-init] Refreshing collation version for template databases..."
      ${psql} \
        -h ${pgHost} -p ${toString pgPort} \
        -U postgres \
        --set=ON_ERROR_STOP=1 \
        -c "ALTER DATABASE template1 REFRESH COLLATION VERSION;" || true
      ${psql} \
        -h ${pgHost} -p ${toString pgPort} \
        -U postgres \
        --set=ON_ERROR_STOP=1 \
        -c "ALTER DATABASE postgres REFRESH COLLATION VERSION;" || true

      echo "[dify-db-init] Creating role '${difyPgUser}' if not exists..."
      ${psql} \
        -h ${pgHost} -p ${toString pgPort} \
        -U postgres \
        --set=ON_ERROR_STOP=1 \
        -c "DO \$\$
          BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${difyPgUser}') THEN
              CREATE ROLE ${difyPgUser} LOGIN;
              RAISE NOTICE 'Role ${difyPgUser} created.';
            ELSE
              RAISE NOTICE 'Role ${difyPgUser} already exists, skipping.';
            END IF;
          END
        \$\$;"

      echo "[dify-db-init] Creating database '${difyPgDb}' if not exists..."
      ${psql} \
        -h ${pgHost} -p ${toString pgPort} \
        -U postgres \
        --set=ON_ERROR_STOP=1 \
        -tAc "SELECT 1 FROM pg_database WHERE datname='${difyPgDb}'" \
        | grep -q 1 || \
        ${psql} \
          -h ${pgHost} -p ${toString pgPort} \
          -U postgres \
          --set=ON_ERROR_STOP=1 \
          -c "CREATE DATABASE ${difyPgDb} OWNER ${difyPgUser};"

      echo "[dify-db-init] Granting privileges to '${difyPgUser}'..."
      ${psql} \
        -h ${pgHost} -p ${toString pgPort} \
        -U postgres \
        -d ${difyPgDb} \
        --set=ON_ERROR_STOP=1 \
        -c "GRANT ALL PRIVILEGES ON DATABASE ${difyPgDb} TO ${difyPgUser};"

      echo "[dify-db-init] Enabling PostgreSQL extensions in '${difyPgDb}'..."
      ${psql} \
        -h ${pgHost} -p ${toString pgPort} \
        -U postgres \
        -d ${difyPgDb} \
        --set=ON_ERROR_STOP=1 \
        -c "
          CREATE EXTENSION IF NOT EXISTS vector;
          CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";
          CREATE EXTENSION IF NOT EXISTS pg_trgm;
        "

      echo "[dify-db-init] Done."
    '';
  };
}
