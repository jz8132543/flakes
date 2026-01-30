# Prowlarr - Indexer Manager
# Based on: https://github.com/Misterio77/nix-config/blob/main/hosts/merope/services/media/prowlarr.nix
{ config, lib, ... }:
{
  services.prowlarr = {
    enable = true;
  };

  services.traefik.dynamicConfigOptions.http = {
    routers.prowlarr = {
      rule = "Host(`prowlarr.${config.networking.domain}`)";
      entryPoints = [ "https" ];
      service = "prowlarr";
    };
    services.prowlarr.loadBalancer.servers = [
      { url = "http://localhost:${toString config.ports.prowlarr}"; }
    ];
  };

  # Disable DynamicUser for stable permissions
  systemd.services.prowlarr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "prowlarr";
    Group = lib.mkForce "prowlarr";
  };

  users = {
    users.prowlarr = {
      home = "/var/lib/prowlarr";
      group = "prowlarr";
      isSystemUser = true;
    };
    groups.prowlarr = { };
  };

  environment.global-persistence.directories = [
    "/var/lib/prowlarr"
  ];
}
