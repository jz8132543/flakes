{
  config,
  ...
}:
{
  config = {
    users.users.iyuu = {
      isSystemUser = true;
      group = "media";
      uid = config.ids.uids.iyuu;
      home = "/var/lib/iyuu";
      createHome = true;
    };
    users.groups.iyuu.gid = config.ids.gids.iyuu;

    sops.templates."iyuu-env" = {
      content = ''
        SERVER_LISTEN_PORT=${toString config.ports.iyuu}
        SERVER_LISTEN_IP=0.0.0.0
        IYUU_TOKEN=${config.sops.placeholder."media/iyuu_token"}
        CONFIG_NOT_MYSQL=1
      '';
      owner = "iyuu";
      group = "media";
    };

    virtualisation.oci-containers.containers.iyuu = {
      image = "docker://iyuucn/iyuuplus:latest";
      volumes = [
        "/data/.state/iyuu:/iyuu"
        "/data/downloads/torrents:/data/downloads/torrents"
      ];
      environment = {
        TZ = "Asia/Shanghai";
        IYUU_ADMIN_USER = "i";
      };
      environmentFiles = [
        config.sops.templates."iyuu-env".path
        config.sops.secrets.password.path
      ];
      extraOptions = [ "--network=host" ];
    };

    services.nginx.virtualHosts.localhost.locations."/iyuu/" = {
      proxyPass = "http://127.0.0.1:8777/";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header X-Forwarded-Prefix /iyuu;
      '';
    };
    services.nginx.virtualHosts.localhost.locations."/iyuu" = {
      return = "301 /iyuu/";
    };

    services.traefik.dynamicConfigOptions.http.routers.nixflix-apps-iyuu = {
      rule = "(Host(`tv.dora.im`) || Host(`${config.networking.fqdn}`)) && PathPrefix(`/iyuu`)";
      entryPoints = [ "https" ];
      service = "nixflix-nginx";
    };
  };
}
