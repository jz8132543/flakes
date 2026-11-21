{ config, lib, ... }:
{
  imports = [ ./rustdesk-server/cluster.nix ];

  # Keep the pre-existing independent deployments on ams0/hkg4 unchanged.
  services.rustdesk-server = {
    enable = lib.mkDefault true;
    openFirewall = lib.mkDefault true;
    signal.relayHosts = lib.mkDefault [ config.networking.fqdn ];
  };
}
