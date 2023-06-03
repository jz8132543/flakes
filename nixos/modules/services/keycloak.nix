{
  config,
  pkgs,
  ...
}: {
  networking.firewall.allowedTCPPorts = [config.ports.ldap];
  services.keycloak = {
    enable = true;
    initialAdminPassword = "qwe";
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
    };
  };
  systemd.services.lldap.serviceConfig.Restart = "always";
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
}
