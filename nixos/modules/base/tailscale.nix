{
  lib,
  config,
  pkgs,
  nixosModules,
  ...
}:
let
  interfaceName = "tailscale0";
  magicDomain = "mag";
in
{
  imports = [ nixosModules.services.restic ];
  services.tailscale = {
    enable = lib.mkDefault true;
    openFirewall = true;
    useRoutingFeatures = "both";
    # Keep DNS management in systemd-resolved under our control so Tailscale
    # does not occasionally promote 100.100.100.100 to the global resolver.
    extraSetFlags = [
      "--netfilter-mode=nodivert"
      "--accept-dns=false"
    ];
    extraDaemonFlags = [ "--no-logs-no-support" ];
  };
  networking = {
    networkmanager.unmanaged = [ interfaceName ];
    # Keep the tunnel interface unmanaged and let systemd-resolved apply
    # the split DNS rule once tailscale0 exists.
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
    after = [ "systemd-resolved.service" ];
    wants = [ "systemd-resolved.service" ];
    serviceConfig = {
      Restart = "always";
      TimeoutStopSec = "5s";
    };
  };

  systemd.services.tailscale-resolved = {
    description = "Register Tailscale MagicDNS with systemd-resolved";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "tailscaled.service"
      "tailscale-setup.service"
      "systemd-resolved.service"
    ];
    after = [
      "tailscaled.service"
      "tailscale-setup.service"
      "systemd-resolved.service"
    ];
    partOf = [
      "tailscaled.service"
      "tailscale-setup.service"
    ];
    bindsTo = [ "tailscaled.service" ];
    path = [
      config.systemd.package
      pkgs.iproute2
      pkgs.coreutils
    ];
    script = ''
      while true; do
        if ip link show dev ${interfaceName} >/dev/null 2>&1; then
          ifindex="$(${pkgs.iproute2}/bin/ip -o link show ${interfaceName} | ${pkgs.coreutils}/bin/cut -d: -f1 | ${pkgs.coreutils}/bin/tr -d ' ')"

          # Write the split-DNS state directly via resolve1 D-Bus so it
          # survives resolvectl oddities on tailscale0 and can be re-applied
          # if tailscale recreates the tunnel device.
          ${config.systemd.package}/bin/busctl call \
            org.freedesktop.resolve1 \
            /org/freedesktop/resolve1 \
            org.freedesktop.resolve1.Manager \
            SetLinkDNS \
            'ia(iay)' \
            "$ifindex" 1 2 4 100 100 100 100

          ${config.systemd.package}/bin/busctl call \
            org.freedesktop.resolve1 \
            /org/freedesktop/resolve1 \
            org.freedesktop.resolve1.Manager \
            SetLinkDomains \
            'ia(sb)' \
            "$ifindex" 1 ${magicDomain} 1

          ${config.systemd.package}/bin/busctl call \
            org.freedesktop.resolve1 \
            /org/freedesktop/resolve1 \
            org.freedesktop.resolve1.Manager \
            SetLinkDefaultRoute \
            'ib' \
            "$ifindex" false
        fi
        sleep 10
      done
    '';
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "2s";
      ExecStop = "${pkgs.runtimeShell} -lc '${config.systemd.package}/bin/resolvectl revert ${interfaceName} || true'";
    };
  };
  services.restic.backups.borgbase.paths = [
    "/var/lib/tailscale/tailscaled.state"
  ];
}
