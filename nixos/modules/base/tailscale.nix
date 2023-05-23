{lib, ...}: {
  services.tailscale = {
    enable = true;
  };
  networking.firewall = {
    allowedUDPPorts = [41641];
  };

  systemd.services.tailscaled.serviceConfig.TimeoutStopSec = "5s";

  environment.persistence."/nix/persist" = {
    directories = ["/var/lib/tailscale"];
  };
}
