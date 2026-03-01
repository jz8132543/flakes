{
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
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "both";
    extraSetFlags = [ "--netfilter-mode=nodivert" ];
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
  # https://github.com/tailscale/tailscale/issues/4254
  services.resolved.enable = true;
  networking.useNetworkd = false;
  # TODO: tailscale cannot connect to some derp when firewall is enabled

  sops.secrets.tailscale_preauth_key = { };

  systemd.services.tailscale-setup = {
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
        --login-server https://ts.${config.networking.domain} \
        --auth-key "file:${config.sops.secrets.tailscale_preauth_key.path}"
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
    after = [
      "dnscrypt-proxy2.service"
      "systemd-resolved.service"
    ];
    serviceConfig = {
      Restart = "always";
      TimeoutStopSec = "5s";
    };
  };
  services.restic.backups.borgbase.paths = [
    "/var/lib/tailscale/tailscaled.state"
  ];
}
