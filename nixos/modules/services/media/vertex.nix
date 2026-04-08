{
  config,
  ...
}:
{
  config = {
    sops.templates."vertex-env" = {
      content = ''
        PASSWORD=${config.sops.placeholder.password}
      '';
    };

    virtualisation.oci-containers.containers.vertex = {
      image = "docker://lswl/vertex:latest";
      volumes = [
        "/data/.state/vertex:/vertex"
        "/data/downloads/torrents:/data/downloads/torrents"
      ];
      environment = {
        TZ = "Asia/Shanghai";
        PORT = toString config.ports.vertex;
        BASE_PATH = "";
        USERNAME = "i";
        HOST = "0.0.0.0";
      };
      environmentFiles = [ config.sops.templates."vertex-env".path ];
      extraOptions = [ "--network=host" ];
    };

    services.traefik.proxies.nixflix-apps-vertex = {
      rule = "Host(`vertex.${config.networking.domain}`) || Host(`vertex.${config.networking.fqdn}`)";
      target = "http://127.0.0.1:${toString config.ports.vertex}";
    };

    services.restic.backups.borgbase.paths = [
      "/data/.state/vertex/db/sql.db"
    ];
  };
}
