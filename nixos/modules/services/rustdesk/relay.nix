{ lib, ... }:
{
  imports = [ ../rustdesk-server/cluster.nix ];

  services.rustdesk-server.cluster = {
    enable = true;
    role = "relay";
    relay.enable = lib.mkDefault true;
  };
}
