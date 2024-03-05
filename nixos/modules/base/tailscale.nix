{
  config,
  pkgs,
  lib,
  ...
}: let
  interfaceName = "tailscale0";
in {
  services.tailscale = {
    enable = true;
    openFirewall = true;
    # useRoutingFeatures = "both";
  };
  networking = {
    networkmanager.unmanaged = [interfaceName];
    firewall = {
      checkReversePath = false;
      trustedInterfaces = ["tailscale0"];
      allowedUDPPorts = [
        config.services.tailscale.port
      ];
    };
  };
  # TODO: tailscale cannot connect to some derp when firewall is enabled
  networking.firewall = {
    allowedUDPPortRanges = [
      {
        from = 0;
        to = 65535;
      }
    ];
    allowedTCPPortRanges = [
      {
        from = 0;
        to = 65535;
      }
    ];
  };

  # systemd.services.tailscale-setup = {
  #   script = ''
  #     sleep 10
  #
  #     if tailscale status; then
  #       echo "tailscale already up, skip"
  #     else
  #       echo "tailscale down, login using auth key"
  #       tailscale up --auth-key "file:${config.sops.secrets."tailscale_tailnet_key".path}"
  #     fi
  #   '';
  #   serviceConfig = {
  #     Type = "oneshot";
  #     RemainAfterExit = true;
  #   };
  #   path = [config.services.tailscale.package];
  #   after = ["tailscaled.service"];
  #   requiredBy = ["tailscaled.service"];
  # };

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
