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
  config = lib.mkMerge [
    {
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
          "sops-nix.service"
          "tailscaled.service"
          "network-online.target"
        ];
        wants = [
          "sops-nix.service"
          "tailscaled.service"
          "network-online.target"
        ];
        wantedBy = [ "multi-user.target" ];
        path = [
          config.services.tailscale.package
          pkgs.jq
          pkgs.coreutils
        ];
        script = ''
          login_server=https://ts.${config.networking.domain}

          # Wait for tailscaled to be ready
          sleep 2

          # Check if already authenticated
          status_json=$(tailscale status --json 2>/dev/null || true)
          status=$(printf '%s' "$status_json" | jq -r '.BackendState // "Unknown"' 2>/dev/null || echo Unknown)
          if [ "$status" = "Running" ]; then
            echo "Tailscale is already running and authenticated."
            exit 0
          fi

          echo "Tailscale not authenticated (state: $status), logging in..."
          timeout 2m tailscale up \
            --reset \
            --login-server "$login_server" \
            --auth-key "file:${config.sops.secrets.tailscale_preauth_key.path}" \
            ${lib.concatStringsSep " " config.services.tailscale.extraSetFlags}
        '';
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "10";
          TimeoutStartSec = "3m";
        };
      };

      systemd.services.tailscale-udp-gro = {
        description = "Tailscale UDP GRO optimization";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [
          pkgs.iproute2
          pkgs.coreutils
          pkgs.ethtool
        ];
        script = ''
          netdev=$(ip route show 0/0 | cut -f5 -d' ' | head -n1 || echo "")
          if [ -n "$netdev" ]; then
            ethtool -K "$netdev" rx-udp-gro-forwarding on rx-gro-list off || true
          fi
        '';
      };

      services.networkd-dispatcher =
        lib.mkIf (config.networking.useNetworkd || config.systemd.network.enable)
          {
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

      environment.etc = lib.mkIf config.networking.networkmanager.enable {
        "NetworkManager/dispatcher.d/99-tailscale-udp-gro" = {
          mode = "0755";
          text = ''
            #!${pkgs.runtimeShell}
            IFACE=$1
            ACTION=$2
            if [ "$ACTION" = "up" ]; then
              ${pkgs.ethtool}/bin/ethtool -K "$IFACE" rx-udp-gro-forwarding on rx-gro-list off || true
            fi
          '';
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

  ];
}
