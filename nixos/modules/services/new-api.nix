{
  config,
  lib,
  nixosModules,
  pkgs,
  ...
}:
let
  cfg = config.services.new-api;
in
{
  imports = [
    nixosModules.services.podman
    nixosModules.services.postgres
    nixosModules.services.traefik
  ];

  options.services.new-api = {
    enable = lib.mkEnableOption "New API - AI Model Gateway & Management Platform";

    image = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/calciumion/new-api:latest";
      description = "Container image for New API.";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "api.${config.networking.domain}";
      description = "Public domain for New API.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = config.ports.new-api;
      description = "Port for New API service.";
    };

    database = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "PostgreSQL host.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 5432;
        description = "PostgreSQL port.";
      };
      name = lib.mkOption {
        type = lib.types.str;
        default = "new_api";
        description = "PostgreSQL database name.";
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = "new_api";
        description = "PostgreSQL database user.";
      };
    };

    oidc = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Keycloak / OIDC single sign-on integration.";
      };
      issuer = lib.mkOption {
        type = lib.types.str;
        default = "https://sso.${config.networking.domain}/realms/users";
        description = "OIDC Issuer URL (Keycloak realm URL).";
      };
      clientId = lib.mkOption {
        type = lib.types.str;
        default = "new-api";
        description = "OIDC Client ID in Keycloak.";
      };
      clientSecretKey = lib.mkOption {
        type = lib.types.str;
        default = "new-api/oidc_client_secret";
        description = "SOPS secret path for OIDC Client Secret.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # 自动在本地 PostgreSQL 中创建数据库与角色
    services.postgresql =
      lib.mkIf (cfg.database.host == "127.0.0.1" || cfg.database.host == "localhost")
        {
          ensureDatabases = [ cfg.database.name ];
          ensureUsers = [
            {
              name = cfg.database.user;
              ensureDBOwnership = true;
            }
          ];
        };

    # 密钥管理：声明全局 password 密钥、CPA API Key，以及在 oidc.enable 时按需加载 OIDC 客户端密钥
    sops.secrets = lib.mkMerge [
      {
        "password" = { };
        "cpa/api_key" = { };
      }
      (lib.mkIf cfg.oidc.enable {
        ${cfg.oidc.clientSecretKey} = { };
      })
    ];

    sops.templates."new-api-env" = lib.mkIf cfg.oidc.enable {
      content = ''
        OIDC_CLIENT_SECRET=${config.sops.placeholder.${cfg.oidc.clientSecretKey}}
      '';
    };

    # 容器服务配置
    virtualisation.oci-containers.containers.new-api = {
      inherit (cfg) image;
      autoStart = true;
      extraOptions = [
        "--network=host"
        "--pull=missing"
      ];
      environment = {
        PORT = toString cfg.port;
        SQL_DSN = "postgres://${cfg.database.user}@${cfg.database.host}:${toString cfg.database.port}/${cfg.database.name}?sslmode=disable";
        GLOBAL_WEB_REDIRECT_URL = "https://${cfg.domain}";
        TZ = config.time.timeZone;
        NODE_TYPE = "master";
      }
      // lib.optionalAttrs cfg.oidc.enable {
        OIDC_ENABLED = "true";
        OIDC_ISSUER = cfg.oidc.issuer;
        OIDC_CLIENT_ID = cfg.oidc.clientId;
        OIDC_REDIRECT_URI = "https://${cfg.domain}/oauth/oidc/callback";
      };
      environmentFiles = lib.optional cfg.oidc.enable config.sops.templates."new-api-env".path;
      volumes = [
        "/var/lib/new-api:/data"
      ];
    };

    systemd.services.podman-new-api = {
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
    };

    # 自动化初始化超级管理员账号 'i' 并自动预置直连本地 CPA 的渠道 (开箱即用)
    systemd.services.new-api-bootstrap = {
      description = "Bootstrap New API administrator 'i' and CPA channel";
      wantedBy = [ "multi-user.target" ];
      after = [
        "podman-new-api.service"
        "postgresql.service"
      ];
      requires = [
        "podman-new-api.service"
        "postgresql.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        PASS="$(cat ${config.sops.secrets."password".path} | tr -d '\n\r')"

        # 等待 New API 在本地端口启动就绪
        for i in $(seq 1 30); do
          if ${pkgs.curl}/bin/curl -s -f http://127.0.0.1:${toString cfg.port}/api/status >/dev/null 2>&1; then
            break
          fi
          sleep 1
        done

        # 检查 users 表是否已由 new-api 容器完成初始化
        TABLE_EXISTS="$(runuser -u postgres -- psql -d ${cfg.database.name} -t -A -c "SELECT to_regclass('public.users');" 2>/dev/null || true)"
        if [ "$TABLE_EXISTS" = "users" ]; then
          runuser -u postgres -- psql -d ${cfg.database.name} -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;" >/dev/null 2>&1 || true

          # 检查是否存在用户 'i'
          USER_I_COUNT="$(runuser -u postgres -- psql -d ${cfg.database.name} -t -A -c "SELECT count(*) FROM users WHERE username = 'i';" 2>/dev/null || echo "0")"
          if [ "$USER_I_COUNT" = "0" ]; then
            # 将默认的初始管理员(id=1)更新为 'i'，并同步密码为 SOPS 的主密码
            runuser -u postgres -- psql -d ${cfg.database.name} -c "
              UPDATE users 
              SET username = 'i', 
                  display_name = 'i', 
                  password = crypt('$PASS', gen_salt('bf')) 
              WHERE id = 1;
            " >/dev/null 2>&1 || true
          else
            # 用户 'i' 已存在，确保密码为 SOPS 的主密码
            runuser -u postgres -- psql -d ${cfg.database.name} -c "
              UPDATE users 
              SET password = crypt('$PASS', gen_salt('bf')) 
              WHERE username = 'i';
            " >/dev/null 2>&1 || true
          fi

          # 自动注册/更新直连本地 CPA 的渠道 (CPA-Local-Gateway)
          CPA_KEY="$(cat ${
            config.sops.secrets."cpa/api_key".path
          } 2>/dev/null | head -n 1 | tr -d '\n\r' || true)"
          if [ -z "$CPA_KEY" ]; then
            CPA_KEY="$PASS"
          fi

          CHANNEL_COUNT="$(runuser -u postgres -- psql -d ${cfg.database.name} -t -A -c "SELECT count(*) FROM channels WHERE name = 'CPA-Local-Gateway';" 2>/dev/null || echo "0")"
          if [ "$CHANNEL_COUNT" = "0" ]; then
            runuser -u postgres -- psql -d ${cfg.database.name} -c "
              INSERT INTO channels (
                name, type, key, base_url, models, \"group\", priority, weight, status, created_time
              ) VALUES (
                'CPA-Local-Gateway',
                1,
                '$CPA_KEY',
                'http://127.0.0.1:8317',
                'gemini-2.5-pro,gemini-2.5-flash,gemini-1.5-pro,gemini-1.5-flash,claude-3-5-sonnet-20241022,gpt-4o,deepseek-chat',
                'default',
                0,
                1,
                1,
                EXTRACT(EPOCH FROM NOW())::bigint
              );
            " >/dev/null 2>&1 || true
          else
            runuser -u postgres -- psql -d ${cfg.database.name} -c "
              UPDATE channels 
              SET key = '$CPA_KEY', base_url = 'http://127.0.0.1:8317' 
              WHERE name = 'CPA-Local-Gateway';
            " >/dev/null 2>&1 || true
          fi
        fi
      '';
    };

    # Traefik 反向代理
    services.traefik.proxies.new-api = {
      rule = "Host(`${cfg.domain}`)";
      target = "http://127.0.0.1:${toString cfg.port}";
    };

    # 状态持久化与目录创建
    systemd.tmpfiles.rules = [
      "d /var/lib/new-api 0750 root root -"
    ];

    environment.global-persistence.directories = [
      "/var/lib/new-api"
    ];
  };
}
