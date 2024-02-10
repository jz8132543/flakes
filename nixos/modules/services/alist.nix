{PG ? "postgres.dora.im", ...}: {
  pkgs,
  lib,
  config,
  ...
}: {
  users = {
    users.alist = {
      isSystemUser = true;
      createHome = false;
      home = "/var/lib/alist";
      group = "alist";
      description = "alist service";
    };

    groups.alist = {};
  };
  systemd.tmpfiles.rules = [
    "d '${config.users.users.alist.home}/temp/aria2' 0777 aria2 aria2 - -"
    "f '/var/lib/aria2/aria2.conf' 0666 aria2 aria2"
  ];

  systemd.services.alist = {
    description = "alist service";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];
    serviceConfig = {
      User = "alist";
      Group = "alist";
      Restart = "on-failure";
      ExecStart = "${pkgs.alist}/bin/alist server --data /var/lib/alist";
      AmbientCapabilities = "cap_net_bind_service";
    };
  };
  services.aria2 = {
    enable = true;
    rpcSecretFile = "/run/credentials/aria2.service/rpcSecretFile";
  };
  systemd.services.aria2.serviceConfig = {
    LoadCredential = lib.mkForce [
      "rpcSecretFile:${pkgs.writeText "secret1" "aria2rpc"}"
    ];
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
  sops.secrets."alist/JWT" = {};

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      alist = {
        rule = "Host(`alist.${config.networking.domain}`)";
        entryPoints = ["https"];
        service = "alist";
      };
    };
    services = {
      alist.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "http://localhost:${toString config.ports.alist}";}];
      };
    };
  };
}
