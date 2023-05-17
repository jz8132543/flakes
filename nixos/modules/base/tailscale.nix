{ lib, ... }:
{
  services.tailscale = {
    enable = true;
  };
  networking.firewall = {
    allowedUDPPorts = [ 41641 ];
  };

  environment.persistence."/nix/persist" = {
    directories = [ "/var/lib/tailscale" ];
  };
}
