{
  config,
  lib,
  ...
}:
{
  deployment = {
    allowLocalDeployment = true;
    targetHost = config.networking.hostName;
    targetPort = lib.lists.findFirst (x: x > 0) 22 config.services.openssh.ports;
  };
}
