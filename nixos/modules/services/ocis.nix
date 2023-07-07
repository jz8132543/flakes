{
  config,
  pkgs,
  ...
}: let
  proxy-config = pkgs.writeText "proxy.yaml" ''
    role_assignment:
      driver: default
      oidc_role_mapper:
        role_claim: groups
        role_mapping:
          admin: ocis_admin
          guest: ocis_guest
          spaceadmin: ocis_space_admin
          user: ocis_user
  '';
in {
  virtualisation.oci-containers.containers = {
    ocis = {
      image = "owncloud/ocis:latest";
      ports = ["127.0.0.1:${toString config.ports.ocis}:9200/tcp"];

      environment = rec {
        OCIS_DOMAIN = "cloud.dora.im";
        OCIS_INSECURE = "false";
        OCIS_LOG_COLOR = "false";
        OCIS_LOG_LEVEL = "error";
        OCIS_URL = "https://${OCIS_DOMAIN}";
        PROXY_TLS = "false";

        OCIS_ADMIN_USER_ID = "i";
        PROXY_ENABLE_BASIC_AUTH = "true";

        # OIDC
        PROXY_AUTOPROVISION_ACCOUNTS = "true";
        OCIS_OIDC_ISSUER = "https://sso.dora.im/realms/users";
        PROXY_OIDC_REWRITE_WELLKNOWN = "true";
        OCIS_EXCLUDE_RUN_SERVICES = "idp";
        GRAPH_ASSIGN_DEFAULT_USER_ROLE = "false";
        WEB_OIDC_CLIENT_ID = "ocis";
        # WEB_OIDC_SCOPE = "openid profile email groups";

        # s3
        STORAGE_USERS_DRIVER = "s3ng";
        STORAGE_SYSTEM_DRIVER = "ocis";
        STORAGE_USERS_S3NG_ENDPOINT = "https://minio.dora.im";
        STORAGE_USERS_S3NG_REGION = "us-east-1";
        STORAGE_USERS_S3NG_BUCKET = "cloud";
      };
      environmentFiles = [config.sops.templates.ocis-env.path];

      entrypoint = "/bin/sh";
      cmd = ["-c" "ocis init | true; ocis server"];
      volumes = [
        "ocis-config:/etc/ocis"
        "ocis-data:/var/lib/ocis"
        "${proxy-config}:/etc/ocis/proxy.yaml:ro"
      ];
    };
  };
  sops.templates.ocis-env.content = ''
    STORAGE_USERS_S3NG_ACCESS_KEY=${config.sops.placeholder."minio/ACCESS_KEY"}
    STORAGE_USERS_S3NG_SECRET_KEY=${config.sops.placeholder."minio/SECRET_KEY"}
    MINIO_DOMAIN=https://minio.dora.im
    MINIO_BUCKET=cloud
    MINIO_ACCESS_KEY=${config.sops.placeholder."minio/ACCESS_KEY"}
    MINIO_SECRET_KEY=${config.sops.placeholder."minio/SECRET_KEY"}
  '';
  sops.secrets = {
    "minio/ACCESS_KEY" = {};
    "minio/SECRET_KEY" = {};
    "mail/ldap" = {};
    "ocis/oidc-secret" = {};
  };
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      ocis = {
        rule = "Host(`cloud.${config.networking.domain}`)";
        entryPoints = ["https"];
        service = "ocis";
      };
    };
    services = {
      ocis.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "http://localhost:${toString config.ports.ocis}";}];
      };
    };
  };
}
