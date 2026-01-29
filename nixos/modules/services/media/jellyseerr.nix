{
  config,
  ...
}:
{
  services.jellyseerr = {
    enable = true;
    port = config.ports.jellyseerr;
    openFirewall = true;
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      jellyseerr = {
        rule = "Host(`seerr.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "jellyseerr";
      };
    };
    services = {
      jellyseerr.loadBalancer.servers = [
        { url = "http://localhost:${toString config.ports.jellyseerr}"; }
      ];
    };
  };
}
