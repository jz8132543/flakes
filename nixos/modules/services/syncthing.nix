{
  config,
  pkgs,
  lib,
  ...
}:

let
  # 统一管理数据定义
  myData = {
    "Obsidian" = {
      id = "Obsidian";
      local = "/var/lib/syncthing/data/Obsidian";
      remote = "alist:/189P/Sync/Obsidian";
      versioning = {
        type = "staggered";
        params = {
          cleanInterval = "3600";
          maxAge = "31536000";
        };
      };
    };
    "Backup-mobi" = {
      id = "Backup-mobi";
      local = "/var/lib/syncthing/data/Backup-mobi";
      remote = "alist:/189P/Sync/Backup-mobi";
      versioning = {
        type = "simple";
        params.keep = "3";
      };
    };
    "Transfer" = {
      id = "Transfer";
      local = "/var/lib/syncthing/data/Transfer";
      remote = "alist:/189F/Sync/Transfer";
      versioning = null;
    };
  };
in
{
  imports = [ ./rclone-bisync.nix ];

  services.genericCloudSync = {
    enable = true;
    inherit (config.services.syncthing) user;
    tasks = lib.mapAttrs (_name: cfg: {
      localPath = cfg.local;
      remotePath = cfg.remote;
      realtime = true;
    }) myData;
  };

  services.syncthing = {
    enable = true;
    guiAddress = "127.0.0.1:${toString config.ports.syncthing}";
    openDefaultPorts = true;
    # urAccepted = -1; # 是否同意匿名报告
    # guiPasswordFile = config.sops.secrets."syncthing/password_hash".path;
    guiPasswordFile = config.sops.secrets."password".path;

    settings.gui = {
      user = "tippy";
      insecureSkipHostcheck = true;
    };
    overrideDevices = false;
    overrideFolders = false;

    settings.folders = lib.mapAttrs (_name: cfg: {
      inherit (cfg) id;
      path = cfg.local;
      inherit (cfg) versioning;
      # 性能优化：针对 4核/8G
      fsWatcherEnabled = true;
      fsWatcherDelayS = 10;
    }) myData;

    # 针对 8G 内存优化数据库
    settings.options = {
      databaseTuning = "large";
      urAccepted = -1; # 是否同意匿名报告
      urSeen = 3;
    };
  };
  users.users.syncthing.homeMode = "770";
  sops.secrets = {
    # "syncthing/password_hash" = {
    "password" = {
      # owner = config.services.syncthing.user;
      mode = "0444";
    };
  };
  systemd.services.syncthing.serviceConfig.ExecStartPre =
    let
      cfg = config.services.syncthing;
    in
    [
      "+${pkgs.coreutils}/bin/mkdir -p ${cfg.dataDir}"
    ]
    ++ (lib.mapAttrsToList (_name: f: "+${pkgs.coreutils}/bin/mkdir -p ${f.local}") myData)
    ++ [
      # "+${pkgs.coreutils}/bin/chown -R ${cfg.user}:${cfg.group} ${cfg.configDir}"
      # # "+${pkgs.coreutils}/bin/chown -R ${cfg.user}:${cfg.group} ${cfg.dataDir}"
      # "+${pkgs.coreutils}/bin/chown -R ${cfg.user}:users ${cfg.dataDir}"
      # "+${pkgs.coreutils}/bin/chmod -R 775 ${cfg.configDir}"
      # "+${pkgs.coreutils}/bin/chmod -R 775 ${cfg.dataDir}"
      "+${pkgs.coreutils}/bin/chown -R ${cfg.user}:users /var/lib/syncthing"
      "+${pkgs.coreutils}/bin/chmod -R 775 /var/lib/syncthing"
    ];

  services.traefik.dynamicConfigOptions.http = {
    routers.syncthing = {
      rule = "Host(`${config.networking.fqdn}`) && PathPrefix(`/syncthing`)";
      entryPoints = [ "https" ];
      service = "syncthing";
      middlewares = [ "strip-prefix" ];
    };
    services.syncthing.loadBalancer.servers = [
      { url = "http://localhost:${toString config.ports.syncthing}"; }
    ];
  };

  environment.global-persistence.directories = [ config.services.syncthing.configDir ];
  services.restic.backups.borgbase.paths = [ config.services.syncthing.configDir ];
}
