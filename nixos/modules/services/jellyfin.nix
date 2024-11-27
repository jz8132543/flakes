{ config, ... }:
let
  portNumber = 8096;
in
{
  services.jellyfin.enable = true;
  users.users.jellyfin.extraGroups = [ "media" ];

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      jellyfin = {
        rule = "Host(`jellyfin.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "jellyfin";
      };
    };
    services = {
      jellyfin.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString portNumber}"; } ];
      };
    };
  };
}
