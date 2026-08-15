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
        # Do not force nodivert globally: exit-node forwarding relies on the
        # normal Tailscale netfilter/NAT path to route packets out to the public
        # Internet. Leaving the default netfilter mode enabled is required for
        # both the exit-node hosts and the local proxy daemon to work correctly.
        extraSetFlags = [
          "--accept-dns=false"
          "--advertise-exit-node"
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
          "sops-install-secrets.service"
          "tailscaled.service"
          "network-online.target"
        ];
        requires = [
          "sops-install-secrets.service"
          "tailscaled.service"
        ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        path = [
          config.services.tailscale.package
          pkgs.jq
          pkgs.coreutils
        ];
        script = ''
          login_server=https://ts.${config.networking.domain}
          preauth_key=${config.sops.secrets.tailscale_preauth_key.path}

          # Wait for tailscaled and the decrypted preauth key to be ready.
          for _ in $(seq 1 60); do
            if [ -s "$preauth_key" ] && tailscale status --json >/dev/null 2>&1; then
              break
            fi
            sleep 1
          done

          if [ ! -s "$preauth_key" ]; then
            echo "Tailscale preauth key is not available: $preauth_key"
            exit 1
          fi

          if ! tailscale status --json >/dev/null 2>&1; then
            echo "Tailscale daemon is not ready."
            exit 1
          fi

          # Check if already authenticated
          status_json=$(tailscale status --json 2>/dev/null || true)
          status=$(printf '%s' "$status_json" | jq -r '.BackendState // "Unknown"' 2>/dev/null || echo Unknown)

          if [ "$status" = "Running" ] || [ "$status" = "Starting" ]; then
            echo "Tailscale is already authenticated (state: $status); reconciling configured flags."
            timeout 2m tailscale up \
              --login-server "$login_server" \
              ${lib.concatStringsSep " " config.services.tailscale.extraSetFlags} > /tmp/tailscale-setup.log 2>&1
            exit_code=$?
            if [ $exit_code -ne 0 ]; then
              echo "tailscale up failed with exit code $exit_code while reconciling flags. Log output:"
              cat /tmp/tailscale-setup.log
              exit $exit_code
            fi
            exit 0
          fi

          if [ "$status" = "NeedsLogin" ] || [ "$status" = "NoState" ]; then
            echo "Tailscale not authenticated (state: $status), logging in..."
            AUTH_KEY=$(cat "${config.sops.secrets.tailscale_preauth_key.path}" | tr -d '\n\r' || true)
            timeout 2m tailscale up \
              --login-server "$login_server" \
              --auth-key "$AUTH_KEY" \
              ${lib.concatStringsSep " " config.services.tailscale.extraSetFlags} > /tmp/tailscale-setup.log 2>&1
            exit_code=$?
            if [ $exit_code -ne 0 ]; then
              echo "tailscale up failed with exit code $exit_code. Log output:"
              cat /tmp/tailscale-setup.log
              exit $exit_code
            fi
          else
            echo "Tailscale is in state $status, no automatic login attempted."
            exit 0
          fi
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
