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
        cert_file = "${config.security.acme.certs."main".directory}/full.pem";
        key_file = "${config.security.acme.certs."main".directory}/key.pem";
      };
    };
  };
  systemd.services.lldap.serviceConfig = {
    User = lib.mkForce "acme";
    Restart = "always";
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
