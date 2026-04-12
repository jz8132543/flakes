{
  config,
  lib,
  pkgs,
  ...
}:
let
  sshRaceDomains = [
    "dora.im"
    "mag"
    "et"
  ];
  sshProxyCommand = "${pkgs.ssh-race}/bin/ssh-race -domains ${lib.concatStringsSep "," sshRaceDomains} %h %p";
in
{
  config.deployment = {
    targetHost = config.networking.hostName;
    targetPort = lib.lists.findFirst (x: x > 0) 22 config.services.openssh.ports;
    sshOptions = [
      "-o"
      "ProxyCommand=${sshProxyCommand}"
    ];
  };
}
