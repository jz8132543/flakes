{
  PG ? "postgres.mag",
  ...
}:
{
  config,
  lib,
  nixosModules,
  ...
}:
{
  imports = [
    nixosModules.services.acme
    nixosModules.services.restic
  ];
  systemd.tmpfiles.rules = [
    "d ' /var/lib/private/lldap/' 0700 lldap lldap - -"
  ];

  networking.firewall.allowedTCPPorts = [ config.ports.ldap ];
  services.keycloak = {
    enable = true;
    database = {
      type = "postgresql";
      host = PG;
      useSSL = false;
      passwordFile = "/dev/null";
    };
    settings = {
      hostname = "sso.dora.im";
      proxy-headers = "xforwarded";
      http-enabled = true;
      http-host = "127.0.0.1";
      http-port = config.ports.keycloak;
    };
  };
  services.lldap = {
    enable = true;
    settings = rec {
      http_host = "localhost";
      http_port = config.ports.lldap;
      ldap_port = config.ports.ldap;
      ldap_base_dn = "dc=dora,dc=im";
      database_url = "postgresql://lldap@${PG}/lldap";
      ldap_user_dn = "sync";
      ldap_user_pass_file = "/run/credentials/lldap.service/password";
      bindDn = "cn=sync,${ldap_base_dn}";
      bindPasswordFile = config.sops.secrets."password".path;
      # force_ldap_user_pass_reset = true;
      # force_update_private_key = true;
      # jwt_secret_file = config.sops.secrets."lldap/jwt_secret".path;
      ldaps_options = {
        enabled = true;
        port = config.ports.ldaps;
        cert_file = "${config.security.acme.certs."main".directory}/cert.pem";
        key_file = "${config.security.acme.certs."main".directory}/key.pem";
      };
      verbose = true;
    };
    environmentFile = config.sops.templates."lldap-env".file;
    environment = {
      # LLDAP_FORCE_UPDATE_PRIVATE_KEY = "true";
      # LLDAP_FORCE_LDAP_USER_PASS_RESET = "true";
    };
  };
  systemd.services.lldap = {
    serviceConfig = {
      AmbientCapabilities = "CAP_NET_BIND_SERVICE";
      SupplementaryGroups = [ "acme" ];
      Restart = "always";
      # EnvironmentFile = config.sops.templates."lldap-env".path;
      LoadCredential = [
        "jwt-secret:${config.sops.secrets."lldap/jwt_secret".path}"
        "password:${config.sops.secrets."password".path}"
      ];
    };
    # restartTriggers = [
    #   config.sops.templates."lldap-env".file
    # ];
  };
  sops.templates."lldap-env" = {
    mode = "0444";
    content = ''
      LLDAP_JWT_SECRET_FILE=/run/credentials/lldap.service/jwt-secret
      LLDAP_SERVER_KEY_SEED=${config.sops.placeholder."lldap/LLDAP_SERVER_KEY_SEED"}
      # LLDAP_FORCE_UPDATE_PRIVATE_KEY=true
      # LLDAP_FORCE_LDAP_USER_PASS_RESET=true
    '';
  };
  sops.secrets = {
    "lldap/LLDAP_SERVER_KEY_SEED" = { };
    "lldap/jwt_secret" = {
      mode = "0444";
    };
    "password" = {
    };
  };
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      keycloak = {
        rule = "Host(`sso.dora.im`)";
        entryPoints = [ "https" ];
        service = "keycloak";
      };
      lldap = {
        rule = "Host(`ldap.dora.im`)";
        entryPoints = [ "https" ];
        service = "lldap";
      };
    };
    services = {
      keycloak.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.keycloak}"; } ];
      };
      lldap.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.lldap}"; } ];
      };
    };
  };
  systemd.services.keycloak = {
    after = [
      "postgresql.service"
      "tailscaled.service"
    ];
    serviceConfig.Restart = lib.mkForce "always";
  };
  services.restic.backups.borgbase.paths = [
    "/var/lib/private/lldap/"
  ];
  systemd.services."restic-backups-borgbase" = {
    # requires = ["lldap.service"];
    after = [ "lldap.service" ];
  };
}
