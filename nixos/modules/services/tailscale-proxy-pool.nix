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
    virtualisation.oci-containers.containers = lib.listToAttrs (
      lib.imap1 (_i: node: {
        name = "ts-proxy-${safeName node}";
        value = {
          image = "docker.io/tailscale/tailscale:latest";
          extraOptions = [
            "--add-host=ts.${config.networking.domain}:host-gateway"
          ];
          volumes = [
            "ts-data-${safeName node}:/var/lib/tailscale"
          ];
          environment = {
            TS_USERSPACE = "true";
            TS_SOCKS5_SERVER = ":1080";
          };
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
            ];
            script = ''
              # Read the reusable auth key for proxies
              AUTH_KEY=$(cat /var/lib/proxy_preauth_key | tr -d '\n\r')

              # Wait for tailscaled to start in the container
              while true; do
                OUTPUT=$(podman exec ts-proxy-${safeName node} tailscale status 2>&1 || true)
                if ! echo "$OUTPUT" | grep -q "failed to connect to local tailscaled"; then
                  break
                fi
                sleep 1
              done

              echo "Logging into Tailscale in container ts-proxy-${safeName node}..."
              podman exec ts-proxy-${safeName node} tailscale up \
                --authkey "$AUTH_KEY" \
                --login-server "https://ts.${config.networking.domain}" \
                --accept-dns=false \
                --reset

              NODE_NAME="${node}"
              NODE_BASE="''${NODE_NAME%.mag}"

              echo "Waiting for exit node $NODE_BASE to become available..."
              while true; do
                 EXIT_NODE_IP=$(podman exec ts-proxy-${safeName node} tailscale status | grep -i "$NODE_BASE" | head -1 | awk '{print $1}')
                 if [ -n "$EXIT_NODE_IP" ]; then
                    if podman exec ts-proxy-${safeName node} tailscale set --exit-node="$EXIT_NODE_IP" --exit-node-allow-lan-access=false; then
                       echo "Successfully set exit node to $EXIT_NODE_IP"
                       break
                    fi
                 fi
                 sleep 5
              done

              # Now that the exit node is set, expose the SOCKS5 proxy using socat
              # Get the container's internal IP address
              CONTAINER_IP=$(podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ts-proxy-${safeName node})

              echo "Starting socat to expose SOCKS5 proxy on 127.0.0.1:${toString (10080 + i)} -> $CONTAINER_IP:1080"
              exec ${pkgs.socat}/bin/socat TCP-LISTEN:${toString (10080 + i)},bind=127.0.0.1,fork,reuseaddr TCP:$CONTAINER_IP:1080
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
