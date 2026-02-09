{
  config,
  lib,
  ...
}:
{
  config = {
    services.autobrr = {
      enable = true;
      secretFile = config.sops.secrets."media/autobrr_session_token".path;
      settings = {
        host = "0.0.0.0";
        port = config.ports.autobrr;
        baseUrl = "/autobrr/";
        database = {
          type = "sqlite";
          dsn = "/data/.state/autobrr/autobrr.db";
        };
      };
    };

    systemd.services.autobrr.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "autobrr";
      Group = lib.mkForce "media";
      ReadWritePaths = [
        "/data/.state/autobrr"
        "/var/lib/autobrr"
      ];
      UMask = "0002";
    };

    users.users.autobrr = {
      isSystemUser = true;
      group = "media";
      uid = config.ids.uids.autobrr;
      home = "/var/lib/autobrr";
      createHome = true;
    };
    users.groups.autobrr.gid = config.ids.gids.autobrr;

    environment.global-persistence.directories = [
      "/data/.state/autobrr"
    ];
  };
}
