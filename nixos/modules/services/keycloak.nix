{
  config,
  lib,
  nixosModules,
  ...
}: {
  imports = [nixosModules.services.acme];
  networking.firewall.allowedTCPPorts = [config.ports.ldap];
  services.keycloak = {
    enable = true;
    database = {
      type = "postgresql";
      host = "postgres.dora.im";
      useSSL = false;
      passwordFile = "/dev/null";
    };
    settings = {
      hostname = "sso.dora.im";
      proxy = "edge";
      http-host = "127.0.0.1";
      http-port = config.ports.keycloak;
    };
  };
  services.lldap = {
    enable = true;
    settings = {
      http_host = "localhost";
      http_port = config.ports.lldap;
      ldap_port = config.ports.ldap;
      ldap_base_dn = "dc=dora,dc=im";
      database_url = "postgresql://lldap@postgres.dora.im/lldap";
      ldap_user_dn = "i";
      ldaps_options = {
        enabled = true;
        port = config.ports.ldaps;
        cert_file = "${config.security.acme.certs."main".directory}/cert.pem";
        key_file = "${config.security.acme.certs."main".directory}/key.pem";
      };
      environment = {
        LLDAP_JWT_SECRET_FILE = config.sops.secrets."lldap/jwt_secret".path;
      };
      verbose = true;
    };
  };
  systemd.services.lldap.serviceConfig = {
    AmbientCapabilities = "CAP_NET_BIND_SERVICE";
    SupplementaryGroups = ["acme"];
    Restart = "always";
    LoadCredential = [
      "jwt-secret:${config.sops.secrets."lldap/jwt_secret".path}"
    ];
  };
  sops.secrets."lldap/jwt_secret" = {
    group = config.systemd.services.lldap.serviceConfig.Group;
    mode = "0440";
  };
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      keycloak = {
        rule = "Host(`sso.dora.im`)";
        entryPoints = ["https"];
        service = "keycloak";
      };
      lldap = {
        rule = "Host(`ldap.dora.im`)";
        entryPoints = ["https"];
        service = "lldap";
      };
    };
    services = {
      keycloak.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "http://localhost:${toString config.ports.keycloak}";}];
      };
      lldap.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "http://localhost:${toString config.ports.lldap}";}];
      };
    };
  };
  systemd.services.keycloak = {
    after = ["postgresql.service" "tailscaled.service"];
    serviceConfig.Restart = lib.mkForce "always";
  };
}
