{
  PG ? "postgres.mag",
  ...
}:
{
  pkgs,
  config,
  nixosModules,
  ...
}:
{
  imports = [ nixosModules.services.aria2 ];
  users = {
    users.alist = {
      isSystemUser = true;
      createHome = false;
      home = "/var/lib/alist";
      group = "alist";
      description = "alist service";
    };

    groups.alist = { };
  };
  systemd.tmpfiles.rules = [
    "d '${config.users.users.alist.home}/temp/aria2' 0777 aria2 aria2 - -"
    "d '${config.users.users.alist.home}/' 0777 alist alist - -"
  ];

  systemd.services.alist = {
    description = "alist service";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      User = "alist";
      Group = "alist";
      Restart = "on-failure";
      ExecStart = "${pkgs.alist}/bin/openlist server --data /var/lib/alist";
      AmbientCapabilities = "cap_net_bind_service";
    };
  };
  services.onlyoffice = {
    enable = true;
    hostname = "office.${config.networking.domain}";
    port = config.ports.onlyoffice;

    postgresHost = PG;
    postgresName = "onlyoffice";
    postgresUser = "onlyoffice";

    jwtSecretFile = config.sops.secrets."onlyoffice/jwtSecretFile".path;
  };

  sops.templates."alist-config" = {
    mode = "0644";
    owner = "alist";
    path = "/var/lib/alist/config.json";
    content = builtins.toJSON {
      site_url = "https://alist.${config.networking.domain}";
      jwt_secret = "${config.sops.placeholder."alist/JWT"}";
      database = {
        type = "postgres";
        host = PG;
        port = 5432;
        user = "alist";
        password = "";
        name = "alist";
        ssl_mode = "prefer";
        db_file = "";
        table_prefix = "x_";
      };
    };
  };
  sops.secrets = {
    "alist/JWT" = { };
    "onlyoffice/jwtSecretFile" = { };
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      alist = {
        rule = "Host(`alist.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "alist";
      };
      office = {
        rule = "Host(`office.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "office";
      };
    };
    services = {
      alist.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.alist}"; } ];
      };
      office.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.onlyoffice}"; } ];
      };
    };
  };
}
