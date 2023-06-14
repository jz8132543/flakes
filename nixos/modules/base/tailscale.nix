{config, ...}: let
  interfaceName = "tailscale0";
in {
  services.tailscale.enable = true;
  networking.networkmanager.unmanaged = [interfaceName];
  networking.firewall.checkReversePath = false;
  networking.firewall.allowedUDPPorts = [
    config.services.tailscale.port
  ];

  systemd.services.tailscaled = {
    before = ["network.target"];
    serviceConfig = {
      Restart = "always";
      TimeoutStopSec = "5s";
    };
  };
}
