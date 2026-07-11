{
  config,
  lib,
  pkgs,
  nixosModules,
  ...
}:
let
  cfg = config.services.knowledge;
  lobePort = 3232;
in
{
  imports = [
    nixosModules.services.podman
    nixosModules.services.postgres
    nixosModules.services.traefik
  ];

  options.services.knowledge = {
    enable = lib.mkEnableOption "LobeChat knowledge workspace";
    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "chat";
    };
    lobeChat = {
      image = lib.mkOption {
        type = lib.types.str;
        default = "lobehub/lobe-chat-database:latest";
      };
      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/lobechat";
      };
    };
    mcp = {
      enable = lib.mkEnableOption "remote MCP bridges";
      obsidian = {
        url = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Obsidian Local REST API URL reachable from nue0.";
        };
        readOnly = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.mcp.enable || cfg.mcp.obsidian.url != "";
        message = "services.knowledge.mcp.obsidian.url must be set when MCP bridges are enabled.";
      }
    ];

    sops.secrets."lobechat/env" = {
      sopsFile = config.sops-file.host;
      key = "lobechat-env";
      owner = "root";
      mode = "0400";
    };

    services.postgresql = {
      ensureDatabases = [ "lobechat" ];
      ensureUsers = [
        {
          name = "lobechat";
          ensureDBOwnership = true;
        }
      ];
    };

    systemd.services.lobechat-db-init = {
      description = "Initialize LobeChat PostgreSQL extensions";
      after = [
        "postgresql.service"
        "postgresql-setup.service"
      ];
      requires = [
        "postgresql.service"
        "postgresql-setup.service"
      ];
      before = [ "podman-lobechat.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "postgres";
      };
      script = ''
        ${pkgs.postgresql_17}/bin/psql --dbname=lobechat --set=ON_ERROR_STOP=1 \
          --command='CREATE EXTENSION IF NOT EXISTS vector'
      '';
    };

    virtualisation.oci-containers.containers.lobechat = {
      image = cfg.lobeChat.image;
      extraOptions = [
        "--network=host"
        "--pull=missing"
      ];
      environment = {
        APP_URL = "https://${cfg.subdomain}.${config.networking.domain}";
        AUTH_KEYCLOAK_ID = "lobechat";
        AUTH_KEYCLOAK_ISSUER = "https://sso.${config.networking.domain}/realms/users";
        AUTH_URL = "https://${cfg.subdomain}.${config.networking.domain}/api/auth";
        DATABASE_URL = "postgresql://lobechat@127.0.0.1:5432/lobechat";
        NEXTAUTH_URL = "https://${cfg.subdomain}.${config.networking.domain}/api/auth";
        NEXT_AUTH_SSO_PROVIDERS = "keycloak";
        NEXT_PUBLIC_AUTH_URL = "https://${cfg.subdomain}.${config.networking.domain}/api/auth";
        NEXT_PUBLIC_SERVICE_MODE = "server";
        PORT = toString lobePort;
        S3_BUCKET = "doraim-lobechat-files";
        S3_ENABLE_PATH_STYLE = "1";
        S3_ENDPOINT = "https://s3.eu-central-003.backblazeb2.com";
        S3_PUBLIC_DOMAIN = "https://f003.backblazeb2.com/file";
        S3_REGION = "eu-central-003";
        S3_SET_ACL = "0";
      };
      environmentFiles = [ config.sops.secrets."lobechat/env".path ];
      volumes = [ "${cfg.lobeChat.dataDir}:/app/data" ];
    };

    systemd.services.podman-lobechat = {
      requires = [ "lobechat-db-init.service" ];
      after = [ "lobechat-db-init.service" ];
    };

    services.traefik.proxies.lobechat = {
      rule = "Host(`${cfg.subdomain}.${config.networking.domain}`)";
      target = "http://127.0.0.1:${toString lobePort}";
    };

    environment.global-persistence.directories = [ cfg.lobeChat.dataDir ];
    services.restic.backups.borgbase.paths = [ cfg.lobeChat.dataDir ];
    systemd.tmpfiles.rules = [ "d ${cfg.lobeChat.dataDir} 0750 root root -" ];
  };
}
