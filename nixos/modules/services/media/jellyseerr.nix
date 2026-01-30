# Jellyseerr - Media Request Manager
# Based on: https://github.com/Misterio77/nix-config/blob/main/hosts/merope/services/media/jellyseerr.nix
{ config, lib, ... }:
{
  services.jellyseerr = {
    enable = true;
    port = config.ports.jellyseerr;
  };

  services.traefik.dynamicConfigOptions.http = {
    routers.jellyseerr = {
      rule = "Host(`seerr.${config.networking.domain}`)";
      entryPoints = [ "https" ];
      service = "jellyseerr";
    };
    services.jellyseerr.loadBalancer.servers = [
      { url = "http://localhost:${toString config.ports.jellyseerr}"; }
    ];
  };

  # Disable DynamicUser for stable permissions
  systemd.services.jellyseerr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "jellyseerr";
    Group = lib.mkForce "jellyseerr";
  };

  users = {
    users.jellyseerr = {
      home = "/var/lib/jellyseerr";
      group = "jellyseerr";
      isSystemUser = true;
    };
    groups.jellyseerr = { };
  };

  environment.global-persistence.directories = [
    "/var/lib/jellyseerr"
  ];
}
