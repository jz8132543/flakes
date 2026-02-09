{
  config,
  lib,
  ...
}:
{
  config = {
    services.flaresolverr = {
      enable = true;
      port = config.ports.flaresolverr;
    };

    systemd.services.flaresolverr.serviceConfig.Restart = lib.mkForce "on-failure";
  };
}
