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
          # 禁用 Tailscale 覆盖 /etc/resolv.conf，避免抢占 127.0.0.1 (dnsmasq)；*.ts 域名已在 dnsmasq 中定向转发至 100.100.100.100
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
        ];
        # A failed daemon start must not cancel the login worker's own retries.
        wants = [
          "tailscaled.service"
          "network-online.target"
        ];
        wantedBy = [ "multi-user.target" ];
        startLimitIntervalSec = 0;
        path = [
          config.services.tailscale.package
          pkgs.jq
          pkgs.coreutils
        ];
        script = ''
          login_server=https://ts.${config.networking.domain}
          preauth_key=${config.sops.secrets.tailscale_preauth_key.path}

          # Keep reconciling after initial login too: Headscale can remove a
          # node while tailscaled itself remains active in NeedsLogin.
          while true; do
            if [ ! -s "$preauth_key" ]; then
              echo "Tailscale preauth key is not available: $preauth_key"
              sleep 10
              continue
            fi

            status_json=$(tailscale status --json 2>/dev/null || true)
            status=$(printf '%s' "$status_json" | jq -r '.BackendState // "Unknown"' 2>/dev/null || echo Unknown)

            case "$status" in
              Running|Starting|Stopped)
                sleep 60
                ;;
              NeedsLogin|NoState)
                echo "Tailscale not authenticated (state: $status), logging in..."
                exit_code=0
                timeout 2m tailscale up \
                  --reset \
                  --login-server "$login_server" \
                  --auth-key "file:$preauth_key" \
                  ${lib.concatStringsSep " " config.services.tailscale.extraSetFlags} > /tmp/tailscale-setup.log 2>&1 || exit_code=$?
                if [ $exit_code -ne 0 ]; then
                  echo "tailscale up failed with exit code $exit_code. Log output:"
                  cat /tmp/tailscale-setup.log
                  sleep 10
                fi
                ;;
              *)
                echo "Tailscale is in state $status; retrying status check."
                sleep 10
                ;;
            esac
          done
        '';
        serviceConfig = {
          # Run as a long-lived state reconciler without blocking boot.
          Type = "exec";
          Restart = "always";
          RestartSec = "10s";
          TimeoutStopSec = "10s";
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
        # tailscaled handles offline links itself. Waiting for network-online
        # can create an ordering cycle with services that need the overlay.
        after = lib.mkForce [ "network-pre.target" ];
        wants = lib.mkForce [ "network-pre.target" ];
        startLimitIntervalSec = 0;
        serviceConfig = {
          Restart = "always";
          RestartSec = "5s";
          TimeoutStartSec = "60s";
          TimeoutStopSec = "5s";
        };
      };
      systemd.services.tailscaled-set = lib.mkIf config.services.tailscale.enable {
        startLimitIntervalSec = 0;
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "5s";
          TimeoutStartSec = "30s";
        };
      };
      services.restic.backups.borgbase.paths = [
        "/var/lib/tailscale/tailscaled.state"
      ];
    }
  ];
}
