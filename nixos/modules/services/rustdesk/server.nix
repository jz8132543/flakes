{ lib, ... }:
{
  imports = [ ../rustdesk-server/cluster.nix ];

  services.rustdesk-server.cluster = {
    enable = true;
    role = "signal";
    relay.enable = lib.mkDefault false;
  };
}
