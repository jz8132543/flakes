{
  config,
  pkgs,
  lib,
  ...
}: {
  services.minio = {
    enable = true;
    listenAddress = "127.0.0.1:${toString config.ports.minio}";
    consoleAddress = "127.0.0.1:${toString config.ports.minio-console}";
    rootCredentialsFile = config.sops.templates."minio-root-credentials".path;
    dataDir = ["/mnt/minio/data"];
    configDir = "/mnt/minio/config";
  };
  # systemd.services.minio.serviceConfig = {
  #   # ExecStartPre = "/bin/sh -c \'echo This is \${MINIO_IDENTITY_LDAP_USERNAME_SEARCH_FILTER}\'";
  #   EnvironmentFile = lib.mkForce [config.sops.templates.minio-env.path];
  # };
  # sops.templates.minio-env = {
  #   owner = "minio";
  #   content = ''
  #     MINIO_ROOT_USER=root
  #     MINIO_ROOT_PASSWORD=qweqweqwe
  #
  #     MINIO_IDENTITY_LDAP_SERVER_ADDR="ldap.dora.im:389"
  #     MINIO_IDENTITY_LDAP_SERVER_INSECURE="on"
  #
  #     # MINIO_IDENTITY_LDAP_USERNAME_FORMAT="uid=%s,ou=people,dc=dora,dc=im"
  #     # MINIO_IDENTITY_LDAP_USERNAME_SEARCH_FILTER="\"(uid=%s)\""
  #
  #     MINIO_IDENTITY_LDAP_USER_DN_SEARCH_BASE_DN="ou=people,dc=dora,dc=im"
  #     MINIO_IDENTITY_LDAP_USER_DN_SEARCH_FILTER="(uid=%s)"
  #
  #     MINIO_IDENTITY_LDAP_GROUP_SEARCH_FILTER="(memberOf=cn=%d,ou=groups,dc=dora,dc=im)"
  #     MINIO_IDENTITY_LDAP_GROUP_SEARCH_BASE_DN="ou=groups,dc=dora,dc=im"
  #
  #     MINIO_IDENTITY_LDAP_LOOKUP_BIND_DN="uid=mail,ou=people,dc=dora,dc=im"
  #     MINIO_IDENTITY_LDAP_LOOKUP_BIND_PASSWORD=${config.sops.placeholder."mail/ldap"}
  #   '';
  # };
  # sops.secrets."mail/ldap" = {};
  sops.secrets."minio/user" = {
    restartUnits = ["minio.service"];
  };
  sops.secrets."minio/password" = {
    restartUnits = ["minio.service"];
  };
  sops.templates."minio-root-credentials".content = ''
    MINIO_ROOT_USER=${config.sops.placeholder."minio/user"}
    MINIO_ROOT_PASSWORD=${config.sops.placeholder."minio/password"}
  '';
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      minio = {
        rule = "Host(`minio.${config.networking.domain}`)";
        entryPoints = ["https"];
        service = "minio";
      };
      minio-console = {
        rule = "Host(`minio-console.${config.networking.domain}`)";
        entryPoints = ["https"];
        service = "minio-console";
      };
    };
    services = {
      minio.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "http://localhost:${toString config.ports.minio}";}];
      };
      minio-console.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "http://localhost:${toString config.ports.minio-console}";}];
      };
    };
  };
  environment.systemPackages = [config.services.minio.package pkgs.minio-client];
}
