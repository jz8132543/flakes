{
  lib,
  config,
  pkgs,
  nixosModules,
  ...
}:
let
  interfaceName = "tailscale0";
in
{
  imports = [ nixosModules.services.restic ];
  services.tailscale = {
    enable = lib.mkDefault true;
    openFirewall = true;
    useRoutingFeatures = "both";
    # Keep DNS ownership in the local dnsmasq frontend so Tailscale does not
    # promote 100.100.100.100 to the global resolver.
    extraSetFlags = [
      "--netfilter-mode=nodivert"
      "--accept-dns=false"
    ];
    extraDaemonFlags = [ "--no-logs-no-support" ];
  };
  networking = {
    networkmanager.unmanaged = [ interfaceName ];
    firewall = {
      # checkReversePath = false;
      trustedInterfaces = [ "tailscale0" ];
      allowedUDPPorts = [
        config.services.tailscale.port
      ];
    };
  };

  sops.secrets.tailscale_preauth_key = { };

  systemd.services.tailscale-setup = {
    enable = lib.mkDefault true;
    description = "Tailscale automatic login";
    after = [
      "tailscaled.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      config.services.tailscale.package
      pkgs.jq
      pkgs.coreutils
    ];
    script = ''
      # Wait for tailscaled to be ready
      sleep 2

      # Check if already authenticated
      status=$(tailscale status --json | jq -r .BackendState)
      if [ "$status" = "Running" ]; then
        echo "Tailscale is already running and authenticated."
        exit 0
      fi

      echo "Tailscale not authenticated (state: $status), logging in..."
      tailscale up \
        --reset \
        --login-server https://ts.${config.networking.domain} \
        --auth-key "file:${config.sops.secrets.tailscale_preauth_key.path}" \
        ${lib.concatStringsSep " " config.services.tailscale.extraSetFlags}
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "10";
    };
  };

  services.networkd-dispatcher = {
    enable = true;
    rules = {
      "tailscale" = {
        onState = [ "routable" ];
        script = ''
          #!${pkgs.runtimeShell}
          netdev=$(${pkgs.iproute2}/bin/ip route show 0/0 | ${pkgs.coreutils}/bin/cut -f5 -d' ' || echo eth0)
          ${pkgs.ethtool}/bin/ethtool -K "$netdev" rx-udp-gro-forwarding on rx-gro-list off || true
        '';
      };
    };
  };

  systemd.services.tailscaled = {
    before = [ "network.target" ];
    serviceConfig = {
      Restart = "always";
      TimeoutStopSec = "5s";
    };
  };
  services.restic.backups.borgbase.paths = [
    "/var/lib/tailscale/tailscaled.state"
  ];
}
