{
  config,
  nixosModules,
  pkgs,
  ...
}:
let
  domain = "chat.dora.im";
  port = config.ports.lobechat;
  dbName = "lobechat";
  dbUser = "lobechat";
  dbHost = "127.0.0.1";
  storage = config.lib.self.data.lobechat.storage;
in
{
  imports = [
    nixosModules.services.podman
    nixosModules.services.postgres
    nixosModules.services.traefik
  ];

  sops.secrets = {
    "lobechat/auth_secret" = { };
    "lobechat/keycloak_client_secret" = { };
    "lobechat/OPENAI_API_KEY" = { };
    "lobechat/b2_key_id" = {
      restartUnits = [ "podman-lobechat.service" ];
    };
    "lobechat/b2_access_key" = {
      restartUnits = [ "podman-lobechat.service" ];
    };
  };

  services.postgresql = {
    ensureDatabases = [ dbName ];
    ensureUsers = [
      {
        name = dbUser;
        ensureDBOwnership = true;
      }
    ];
  };

  virtualisation.oci-containers.containers.lobechat = {
    image = "lobehub/lobe-chat-database:latest";
    autoStart = true;
    extraOptions = [ "--network=host" ];
    environment = {
      APP_URL = "https://${domain}";
      AUTH_URL = "https://${domain}/api/auth";
      DATABASE_URL = "postgresql://${dbUser}@${dbHost}:5432/${dbName}";
      FEATURE_FLAGS = "-market";
      PORT = toString port;
      NEXT_PUBLIC_ENABLE_WELCOMES = "false";
      NEXT_PUBLIC_AUTH_URL = "https://${domain}/api/auth";
      NEXT_PUBLIC_SERVICE_MODE = "server";
      NEXTAUTH_URL = "https://${domain}/api/auth";
      NEXT_AUTH_SSO_PROVIDERS = "keycloak";
      AUTH_KEYCLOAK_ID = "lobechat";
      AUTH_KEYCLOAK_ISSUER = "https://sso.dora.im/realms/users";
      S3_BUCKET = storage.bucket;
      S3_ENABLE_PATH_STYLE = "1";
      S3_ENDPOINT = storage.endpoint;
      S3_PUBLIC_DOMAIN = storage.publicDomain;
      S3_REGION = storage.region;
      S3_SET_ACL = "0";
    };
    environmentFiles = [ config.sops.templates."lobechat-env".path ];
    volumes = [
      "/var/lib/lobechat:/app/data"
    ];
  };

  systemd.services.podman-lobechat = {
    after = [
      "lobechat-db-init.service"
    ];
    requires = [
      "lobechat-db-init.service"
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
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.postgresql}/bin/psql \
        --dbname=${dbName} \
        --set=ON_ERROR_STOP=1 \
        --command='CREATE EXTENSION IF NOT EXISTS vector'
    '';
  };

  sops.templates."lobechat-env".content = ''
    AUTH_SECRET=${config.sops.placeholder."lobechat/auth_secret"}
    AUTH_KEYCLOAK_SECRET=${config.sops.placeholder."lobechat/keycloak_client_secret"}
    KEY_VAULTS_SECRET=${config.sops.placeholder."lobechat/auth_secret"}
    S3_ACCESS_KEY_ID=${config.sops.placeholder."lobechat/b2_key_id"}
    S3_SECRET_ACCESS_KEY=${config.sops.placeholder."lobechat/b2_access_key"}
    OPENAI_PROXY_URL=https://aigw.c5y.moe/v1
    OPENAI_API_KEY=${config.sops.placeholder."lobechat/OPENAI_API_KEY"}
  '';

  systemd.tmpfiles.rules = [
    "d /var/lib/lobechat 0750 root root -"
  ];

  services.traefik.proxies.lobechat = {
    rule = "Host(`${domain}`)";
    target = "http://127.0.0.1:${toString port}";
  };
}
