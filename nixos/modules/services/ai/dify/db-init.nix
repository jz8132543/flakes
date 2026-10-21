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
  pkgs,
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

  # ── 容器初始化迁移完成后，自动播种管理员 i、跳过向导并预置 degoog 工具 ─────────
  systemd.services.dify-bootstrap = {
    description = "Bootstrap Dify administrator 'i', Keycloak SSO workspace, and degoog tool";
    after = [
      "podman-dify-api.service"
      "postgresql.service"
      "sops-install-secrets.service"
    ];
    wants = [
      "podman-dify-api.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "postgres";
    };
    path = with pkgs; [
      coreutils
      postgresql
      curl
      (python3.withPackages (ps: with ps; [ psycopg2 ]))
    ];
    script = ''
            set -euo pipefail

            echo "[dify-bootstrap] Waiting for Dify database migrations to create tables..."
            for i in $(seq 1 60); do
              ACCOUNTS_EXISTS="$(${psql} -h ${pgHost} -p ${toString pgPort} -U postgres -d ${difyPgDb} -tAc "SELECT to_regclass('public.accounts');" 2>/dev/null || true)"
              if [ "$ACCOUNTS_EXISTS" = "accounts" ]; then
                break
              fi
              sleep 3
            done

            PASS_FILE="${config.sops.secrets."password".path}"
            if [ ! -f "$PASS_FILE" ]; then
              echo "[dify-bootstrap] SOPS password file not ready, skipping seed."
              exit 0
            fi

            python3 - "$PASS_FILE" << 'PYEOF'
      import base64
      import hashlib
      import json
      import os
      import secrets
      import sys
      import uuid
      import psycopg2

      pass_file = sys.argv[1]
      with open(pass_file, "r") as f:
          raw_password = f.read().strip()

      conn = psycopg2.connect(
          dbname="${difyPgDb}",
          user="postgres",
          host="${pgHost}",
          port=${toString pgPort}
      )
      cur = conn.cursor()

      # 1. Bypass setup wizard
      cur.execute("SELECT to_regclass('public.dify_setups');")
      if cur.fetchone()[0]:
          cur.execute("SELECT count(*) FROM dify_setups;")
          count = cur.fetchone()[0]
          if count == 0:
              cur.execute("INSERT INTO dify_setups (version, setup_at) VALUES ('0.15.3', NOW());")
              conn.commit()

      # 2. Hash password with Dify's PBKDF2-SHA256 algorithm
      salt = base64.b64encode(secrets.token_bytes(16)).decode('utf-8')
      password_hash = base64.b64encode(
          hashlib.pbkdf2_hmac(
              'sha256',
              raw_password.encode('utf-8'),
              salt.encode('utf-8'),
              100000
          )
      ).decode('utf-8')

      # 3. Upsert admin account 'i'
      admin_email = "i@${config.networking.domain}"
      cur.execute("SELECT id FROM accounts WHERE email = %s;", (admin_email,))
      row = cur.fetchone()
      if not row:
          account_id = str(uuid.uuid4())
          cur.execute("""
              INSERT INTO accounts (
                  id, name, email, password, password_salt,
                  interface_language, timezone, status, created_at, updated_at
              ) VALUES (
                  %s, 'i', %s, %s, %s,
                  'zh-Hans', 'Asia/Shanghai', 'active', NOW(), NOW()
              );
          """, (account_id, admin_email, password_hash, salt))
          conn.commit()
      else:
          account_id = row[0]
          cur.execute("""
              UPDATE accounts
              SET password = %s, password_salt = %s, status = 'active'
              WHERE id = %s;
          """, (password_hash, salt, account_id))
          conn.commit()

      # 4. Ensure tenant and tenant_account_joins
      cur.execute("SELECT tenant_id FROM tenant_account_joins WHERE account_id = %s;", (account_id,))
      join_row = cur.fetchone()
      if not join_row:
          cur.execute("SELECT id FROM tenants LIMIT 1;")
          t_row = cur.fetchone()
          if t_row:
              tenant_id = t_row[0]
          else:
              tenant_id = str(uuid.uuid4())
              cur.execute("""
                  INSERT INTO tenants (id, name, plan, status, created_at, updated_at)
                  VALUES (%s, 'i Workspace', 'basic', 'normal', NOW(), NOW());
              """, (tenant_id,))
          cur.execute("""
              INSERT INTO tenant_account_joins (id, tenant_id, account_id, role, created_at, updated_at)
              VALUES (%s, %s, %s, 'owner', NOW(), NOW());
          """, (str(uuid.uuid4()), tenant_id, account_id))
          conn.commit()
      else:
          tenant_id = join_row[0]

      # 5. Injects Degoog Search tool into tool_api_providers if table exists
      cur.execute("SELECT to_regclass('public.tool_api_providers');")
      if cur.fetchone()[0]:
          cur.execute("SELECT count(*) FROM tool_api_providers WHERE name = 'degoog';")
          if cur.fetchone()[0] == 0:
              degoog_openapi = {
                  "openapi": "3.0.0",
                  "info": {
                      "title": "Degoog Web Search & Article Reader",
                      "version": "1.0.0",
                      "description": "Local privacy web search and clean webpage reader"
                  },
                  "servers": [{"url": "http://127.0.0.1:${toString config.ports.degoog-mcp}"}],
                  "paths": {
                      "/search": {
                          "get": {
                              "operationId": "search_web",
                              "summary": "Search the web via Degoog",
                              "parameters": [
                                  {"name": "q", "in": "query", "required": True, "schema": {"type": "string"}, "description": "Search query keywords"},
                                  {"name": "limit", "in": "query", "required": False, "schema": {"type": "integer", "default": 5}, "description": "Max results"}
                              ],
                              "responses": {"200": {"description": "Search results"}}
                          }
                      },
                      "/fetch": {
                          "get": {
                              "operationId": "fetch_webpage",
                              "summary": "Extract clean webpage text",
                              "parameters": [
                                  {"name": "url", "in": "query", "required": True, "schema": {"type": "string"}, "description": "Webpage URL to read"}
                              ],
                              "responses": {"200": {"description": "Extracted text content"}}
                          }
                      }
                  }
              }
              tools_str = json.dumps([
                  {"name": "search_web", "label": "Search Web", "description": "Search the web via Degoog"},
                  {"name": "fetch_webpage", "label": "Fetch Webpage", "description": "Extract clean webpage text"}
              ])
              cur.execute("""
                  INSERT INTO tool_api_providers (
                      id, user_id, tenant_id, name, schema, schema_type_str,
                      tools_str, icon, credentials_str, description,
                      custom_disclaimer, created_at, updated_at
                  ) VALUES (
                      %s, %s, %s, 'degoog', %s, 'openapi',
                      %s, '{"content":"🔍","background":"#2563EB"}', '{}',
                      'Local privacy search and article reader',
                      "", NOW(), NOW()
                  );
              """, (str(uuid.uuid4()), account_id, tenant_id, json.dumps(degoog_openapi), tools_str))
              conn.commit()

      cur.close()
      conn.close()
      print("[dify-bootstrap] Admin 'i', workspace, setup bypass, and degoog tool initialized successfully.")
      PYEOF
    '';
  };
}
