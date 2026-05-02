# VJ Save Restricted Content Bot
# Uses Pyrogram (needs API_ID + API_HASH) + Motor (MongoDB only, cannot use Postgres)
# Runs two containers: vj-save-mongodb + vj-save, connected via a shared podman network
# { nixosModules, ... }:
{
  config,
  pkgs,
  nixosModules,
  ...
}:
{
  imports = [
    nixosModules.services.podman
  ];

  # Create a shared network so vj-save can reach vj-save-mongodb by hostname
  systemd.services.podman-network-vj-save = {
    description = "Create podman network for vj-save";
    before = [
      "podman-vj-save-mongodb.service"
      "podman-vj-save.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.podman}/bin/podman network exists vj-save || ${pkgs.podman}/bin/podman network create vj-save";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/vj-save 0700 root root -"
    "d /var/lib/vj-save/mongodb 0700 root root -"
  ];

  virtualisation.oci-containers.containers = {
    vj-save-mongodb = {
      image = "mongo:7";
      extraOptions = [
        "--network=vj-save"
        "--network-alias=vj-save-mongodb"
      ];
      volumes = [
        "/var/lib/vj-save/mongodb:/data/db:rw"
      ];
      log-driver = "journald";
    };

    vj-save = {
      image = "ghcr.io/vjbots/vj-save-restricted-content:TechVJ";
      extraOptions = [
        "--network=vj-save"
      ];
      dependsOn = [ "vj-save-mongodb" ];
      environmentFiles = [ config.sops.templates."vj-save".path ];
      log-driver = "journald";
    };
  };

  # Make the mongodb service wait for the network to be ready
  systemd.services.podman-vj-save-mongodb = {
    after = [ "podman-network-vj-save.service" ];
    requires = [ "podman-network-vj-save.service" ];
  };

  systemd.services.podman-vj-save = {
    after = [
      "podman-network-vj-save.service"
      "podman-vj-save-mongodb.service"
    ];
    requires = [
      "podman-network-vj-save.service"
      "podman-vj-save-mongodb.service"
    ];
  };

  sops.secrets = {
    "telegram/token" = { };
    "telegram/userid" = { };
    "telegram/vj_saver_channelid" = { };
    "telegram/api_id" = { };
    "telegram/api_hash" = { };
  };

  # sops-nix renders secrets into the env file at runtime before containers start
  sops.templates."vj-save" = {
    content = ''
      BOT_TOKEN=${config.sops.placeholder."telegram/token"}
      API_ID=${config.sops.placeholder."telegram/api_id"}
      API_HASH=${config.sops.placeholder."telegram/api_hash"}
      ADMINS=${config.sops.placeholder."telegram/userid"}
      CHANNEL_ID=${config.sops.placeholder."telegram/vj_saver_channelid"}
      DB_URI=mongodb://vj-save-mongodb:27017
      DB_NAME=vjsavecontentbot
      LOGIN_SYSTEM=True
      WAITING_TIME=10
      ERROR_MESSAGE=True
    '';
  };
}
