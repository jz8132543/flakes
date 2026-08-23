{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.tailscale-proxy-pool;
  safeName = node: lib.replaceStrings [ "." ] [ "_" ] node;
in
{
  options.services.tailscale-proxy-pool = {
    enable = lib.mkEnableOption "Tailscale local Docker proxy pool";

    exitNodes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Tailscale Magic DNS names to use as Exit Nodes for the proxy pool.";
    };

    poolPort = lib.mkOption {
      type = lib.types.port;
      default = 10080;
      description = "HAProxy load-balanced SOCKS5 pool port (on localhost).";
    };
  };

  config = lib.mkIf cfg.enable {

    # iptables kernel modules are required for tailscale in kernel TUN mode inside containers.
    # NixOS defaults to nftables, so these legacy modules may not be loaded otherwise.
    # Containers with NET_ADMIN can use iptables only if the host kernel has these loaded.
    boot.kernelModules = [
      "ip_tables"
      "iptable_filter"
      "iptable_nat"
      "iptable_mangle"
    ];

    virtualisation.oci-containers.containers = lib.listToAttrs (
      lib.imap1 (_i: node: {
        name = "ts-proxy-${safeName node}";
        value = {
          image = "docker.io/tailscale/tailscale:latest";

          # Run tailscaled directly (bypass containerboot).
          # Kernel TUN mode: exit node enforced at kernel routing level.
          # When exit node is set, tailscale installs 0.0.0.0/1 and 128.0.0.0/1
          # routes via tun0, overriding the eth0 default route.
          # Traffic cannot leak via eth0 — fail-closed by the kernel.
          entrypoint = "/usr/local/bin/tailscaled";
          cmd = [
            "--statedir=/var/lib/tailscale"
            "--socket=/var/run/tailscale/tailscaled.sock"
            "--socks5-server=:1080"
          ];

          extraOptions = [
            "--add-host=ts.${config.networking.domain}:host-gateway"
            "--add-host=${config.networking.fqdn}:host-gateway"
            # Required for kernel TUN mode
            "--cap-add=NET_ADMIN"
            "--device=/dev/net/tun"
            # Ephemeral state: always fresh on restart
            "--tmpfs=/var/lib/tailscale:size=64m"
          ];
        };
      }) cfg.exitNodes
    );

    systemd.services =
      lib.listToAttrs (
        lib.imap1 (i: node: {
          name = "ts-proxy-setup-${safeName node}";
          value = {
            description = "Tailscale setup for ts-proxy-${safeName node}";
            after = [
              "podman-ts-proxy-${safeName node}.service"
              "sops-install-secrets.service"
            ];
            requires = [
              "podman-ts-proxy-${safeName node}.service"
            ];
            wantedBy = [ "multi-user.target" ];
            path = [
              pkgs.podman
              pkgs.coreutils
              pkgs.gawk
              pkgs.gnugrep
              pkgs.socat
            ];
            script = ''
              AUTH_KEY=$(cat "${config.sops.secrets.tailscale_preauth_key.path}" | tr -d '\n\r')

              # --- Phase 1: authenticate ---
              MAX_WAIT=120
              WAITED=0
              while true; do
                OUTPUT=$(podman exec ts-proxy-${safeName node} tailscale status 2>&1 || true)
                if echo "$OUTPUT" | grep -qE 'idle|active|offers exit node'; then
                  break
                fi
                if echo "$OUTPUT" | grep -qiE 'Logged out|NeedsLogin|NoState'; then
                  podman exec ts-proxy-${safeName node} tailscale up \
                    --authkey "$AUTH_KEY" \
                    --login-server "https://ts.${config.networking.domain}" \
                    --accept-dns=false \
                    --reset 2>&1 || true
                fi
                sleep 3
                WAITED=$((WAITED + 3))
                if [ $WAITED -ge $MAX_WAIT ]; then
                  echo "Timeout waiting for tailscale login in ts-proxy-${safeName node}"
                  exit 1
                fi
              done
              echo "Tailscale authenticated in ts-proxy-${safeName node}"

              # --- Phase 2: set exit node (wait until available) ---
              NODE_NAME="${node}"
              NODE_BASE="''${NODE_NAME%.mag}"

              echo "Waiting for exit node $NODE_BASE to become available..."
              while true; do
                EXIT_NODE_IP=$(podman exec ts-proxy-${safeName node} tailscale status \
                  | awk -v node="$NODE_BASE" '$2 == node {print $1}')
                if [ -n "$EXIT_NODE_IP" ]; then
                  if podman exec ts-proxy-${safeName node} tailscale set \
                      --exit-node="$EXIT_NODE_IP" \
                      --exit-node-allow-lan-access=true; then
                    echo "Successfully set exit node to $EXIT_NODE_IP ($NODE_BASE)"
                    break
                  fi
                fi
                sleep 5
              done

              # --- Phase 3: expose SOCKS5 via socat ONLY after exit node is confirmed ---
              # Kernel routing now enforces: all traffic via tun0 → exit node.
              CONTAINER_IP=$(podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ts-proxy-${safeName node})
              echo "Starting socat: 127.0.0.1:${toString (10080 + i)} -> $CONTAINER_IP:1080"
              exec socat TCP-LISTEN:${toString (10080 + i)},bind=127.0.0.1,fork,reuseaddr \
                TCP:$CONTAINER_IP:1080
            '';
            serviceConfig = {
              Type = "simple";
              Restart = "always";
              RestartSec = "10";
            };
          };
        }) cfg.exitNodes
      )
      // {
        haproxy.reloadIfChanged = true;
      };

    services.haproxy = {
      enable = true;
      config = ''
        global
          log stdout format raw local0
          maxconn 2000
          user haproxy
          group haproxy

        defaults
          log global
          mode tcp
          option tcplog
          timeout connect 5s
          timeout client  300s
          timeout server  300s
          timeout check   8s

        frontend socks5_front
          bind 127.0.0.1:${toString cfg.poolPort}
          default_backend socks5_back

        backend socks5_back
          balance roundrobin
          option tcp-check
          default-server inter 10s fall 2 rise 1
          ${lib.concatStringsSep "\n          " (
            lib.imap1 (
              i: node: "server proxy_${safeName node} 127.0.0.1:${toString (10080 + i)} check"
            ) cfg.exitNodes
          )}
      '';
    };
  };
}
