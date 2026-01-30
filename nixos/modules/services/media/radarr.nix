# Radarr - Movie Manager
# Based on: https://github.com/Misterio77/nix-config/blob/main/hosts/merope/services/media/radarr.nix
{ config, lib, ... }:
{
  services.radarr = {
    enable = true;
    group = "media";
  };

  services.traefik.dynamicConfigOptions.http = {
    routers.radarr = {
      rule = "Host(`radarr.${config.networking.domain}`)";
      entryPoints = [ "https" ];
      service = "radarr";
    };
    services.radarr.loadBalancer.servers = [
      { url = "http://localhost:${toString config.ports.radarr}"; }
    ];
  };

  # Add radarr to qbittorrent's group for hard-linking
  users.users.radarr.extraGroups = [ "media" ];

  # Disable DynamicUser for stable permissions
  systemd.services.radarr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "radarr";
    Group = lib.mkForce "media";
  };

  environment.global-persistence.directories = [
    config.services.radarr.dataDir
  ];

  # Media directory for movies
  systemd.tmpfiles.settings.srv-media-movies."/srv/media/movies".d = {
    inherit (config.services.radarr) user;
    inherit (config.services.radarr) group;
    mode = "0775";
  };
}
