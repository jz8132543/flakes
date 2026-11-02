{
  config,
  lib,
  ...
}:
let
  sshHost = (config.programs.ssh.customHosts or { }).${config.networking.hostName} or { };
in
{
  config.deployment = {
    targetHost = config.networking.hostName;
    targetPort = sshHost.port or (lib.lists.findFirst (x: x > 0) 22 config.services.openssh.ports);
  };
}
