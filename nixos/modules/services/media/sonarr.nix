# Sonarr - TV Series Manager
# Based on: https://github.com/Misterio77/nix-config/blob/main/hosts/merope/services/media/sonarr.nix
{ config, lib, ... }:
{
  services.sonarr = {
    enable = true;
    group = "media";
  };

  services.traefik.dynamicConfigOptions.http = {
    routers.sonarr = {
      rule = "Host(`sonarr.${config.networking.domain}`)";
      entryPoints = [ "https" ];
      service = "sonarr";
    };
    services.sonarr.loadBalancer.servers = [
      { url = "http://localhost:${toString config.ports.sonarr}"; }
    ];
  };

  # Add sonarr to qbittorrent's group for hard-linking
  users.users.sonarr.extraGroups = [ "media" ];

  # Disable DynamicUser for stable permissions
  systemd.services.sonarr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "sonarr";
    Group = lib.mkForce "media";
  };

  environment.global-persistence.directories = [
    config.services.sonarr.dataDir
  ];

  # Media directory for TV shows
  systemd.tmpfiles.settings.srv-media-tv."/srv/media/tv".d = {
    inherit (config.services.sonarr) user;
    inherit (config.services.sonarr) group;
    mode = "0775";
  };
}
