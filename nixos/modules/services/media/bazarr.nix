# Bazarr - Subtitle Manager
# Based on: https://github.com/Misterio77/nix-config/blob/main/hosts/merope/services/media/bazarr.nix
{ config, lib, ... }:
{
  services.bazarr = {
    enable = true;
    group = "media";
  };

  services.traefik.dynamicConfigOptions.http = {
    routers.bazarr = {
      rule = "Host(`bazarr.${config.networking.domain}`)";
      entryPoints = [ "https" ];
      service = "bazarr";
    };
    services.bazarr.loadBalancer.servers = [
      { url = "http://localhost:${toString config.ports.bazarr}"; }
    ];
  };

  # Add bazarr to sonarr and radarr groups
  # So that it can write subtitles to the library dirs
  users.users.bazarr.extraGroups = [
    config.services.sonarr.group
    config.services.radarr.group
  ];

  # Disable DynamicUser for stable permissions
  systemd.services.bazarr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "bazarr";
    Group = lib.mkForce "media";
  };

  environment.global-persistence.directories = [
    config.services.bazarr.dataDir
  ];
}
