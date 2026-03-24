{
  config,
  lib,
  ...
}:
{
  config.deployment = {
    targetHost = config.networking.hostName;
    targetPort = lib.lists.findFirst (x: x > 0) 22 config.services.openssh.ports;
  };
}
