# qBittorrent - Torrent Client
# Based on: https://github.com/Misterio77/nix-config/blob/main/hosts/merope/services/media/deluge.nix
# (Using qBittorrent instead of Deluge)
{ config, lib, ... }:
{
  services.qbittorrent = {
    enable = true;
    user = "qbittorrent";
    group = "media";
    profileDir = "/var/lib/qbittorrent";
    webuiPort = config.ports.qbittorrent;
    openFirewall = true;
  };

  services.traefik.dynamicConfigOptions.http = {
    routers.qbittorrent = {
      rule = "Host(`qbit.${config.networking.domain}`)";
      entryPoints = [ "https" ];
      service = "qbittorrent";
    };
    services.qbittorrent.loadBalancer.servers = [
      { url = "http://localhost:${toString config.ports.qbittorrent}"; }
    ];
  };

  # Disable DynamicUser for stable permissions
  systemd.services.qbittorrent.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "qbittorrent";
    Group = lib.mkForce "media";
  };

  users = {
    users.qbittorrent = {
      home = "/var/lib/qbittorrent";
      group = "media";
      isSystemUser = true;
      extraGroups = [ "media" ];
    };
  };

  environment.global-persistence.directories = [
    "/var/lib/qbittorrent"
  ];

  # Torrent directories
  systemd.tmpfiles.settings.srv-torrents = {
    "/srv/torrents".d = {
      user = "qbittorrent";
      group = "media";
      mode = "0775";
    };
    "/srv/torrents/downloading".d = {
      user = "qbittorrent";
      group = "media";
      mode = "0775";
    };
    "/srv/torrents/completed".d = {
      user = "qbittorrent";
      group = "media";
      mode = "0775";
    };
  };
}
