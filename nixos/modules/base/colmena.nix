{
  config,
  lib,
  ...
}:
{
  config.deployment = {
    targetHost = lib.mkDefault config.networking.hostName;
    targetPort = lib.mkDefault (lib.lists.findFirst (x: x > 0) 22 config.services.openssh.ports);
  };
}
