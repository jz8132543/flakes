{ lib, ... }:
{
  services.tailscale = {
    enable = true;
  };
  networking.firewall = {
    allowedUDPPorts = [ 41641 ]; # Facilitate firewall punching
  };

  environment.persistence."/nix/persist" = {
    directories = [ "/var/lib/tailscale" ];
  };
}
