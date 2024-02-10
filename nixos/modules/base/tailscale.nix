{
  config,
  pkgs,
  ...
}: let
  interfaceName = "tailscale0";
in {
  services.tailscale = {
    openFirewall = true;
    enable = true;
  };
  networking.networkmanager.unmanaged = [interfaceName];
  networking.firewall.checkReversePath = false;
  # networking.firewall.trustedInterfaces = ["tailscale0"];
  networking.firewall.allowedUDPPorts = [
    config.services.tailscale.port
  ];

  services.networkd-dispatcher = {
    enable = true;
    rules = {
      "tailscale" = {
        onState = ["routable"];
        script = ''
          #!${pkgs.runtimeShell}
          netdev=$(${pkgs.iproute2}/bin/ip route show 0/0 | ${pkgs.coreutils}/bin/cut -f5 -d' ' || echo eth0)
          ${pkgs.ethtool}/bin/ethtool -K "$netdev" rx-udp-gro-forwarding on rx-gro-list off || true
        '';
      };
    };
  };

  systemd.services.tailscaled = {
    before = ["network.target"];
    serviceConfig = {
      Restart = "always";
      TimeoutStopSec = "5s";
    };
  };
}
