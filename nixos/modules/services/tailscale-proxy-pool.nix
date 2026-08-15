{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.tailscale-proxy-pool;

  socks5HealthCheck = pkgs.writeShellScript "haproxy-check-socks5" ''
    set -eu

    # HAProxy can expose the server endpoint through environment variables or
    # positional arguments depending on the check mode and version. Accept both.
    addr="''${ADDR:-}"
    if [ -z "$addr" ]; then
      addr="''${HAPROXY_SERVER_ADDR:-}"
    fi
    if [ -z "$addr" ]; then
      addr="''${1:-}"
    fi
    if [ -z "$addr" ]; then
      addr="''${3:-127.0.0.1}"
    fi

    port="''${PORT:-}"
    if [ -z "$port" ]; then
      port="''${HAPROXY_SERVER_PORT:-}"
    fi
    if [ -z "$port" ]; then
      port="''${2:-}"
    fi
    if [ -z "$port" ]; then
      port="''${4:-}"
    fi

    if [ -z "$port" ] || [ "$port" = "0" ]; then
      echo "Missing SOCKS5 port for health check" >&2
      exit 1
    fi

    direct_ip=$(${pkgs.curl}/bin/curl \
      --connect-timeout 3 \
      --max-time 8 \
      --silent \
      --show-error \
      --fail \
      http://ip.sb 2>/dev/null || true)

    proxy_ip=$(${pkgs.curl}/bin/curl \
      --connect-timeout 3 \
      --max-time 8 \
      --silent \
      --show-error \
      --fail \
      --proxy "socks5h://$addr:$port" \
      http://ip.sb 2>/dev/null || true)

    if [ -z "$proxy_ip" ]; then
      echo "SOCKS5 proxy check failed for $addr:$port" >&2
      exit 1
    fi

    if [ -n "$direct_ip" ] && [ "$proxy_ip" = "$direct_ip" ]; then
      echo "Proxy returned the direct host IP; refusing to use it as an exit node" >&2
      exit 1
    fi

    case "$proxy_ip" in
      10.*|127.*|169.254.*|172.16.*|172.17.*|172.18.*|172.19.*|172.20.*|172.21.*|172.22.*|172.23.*|172.24.*|172.25.*|172.26.*|172.27.*|172.28.*|172.29.*|172.30.*|172.31.*|192.168.*|0.0.0.0|255.255.255.255)
        echo "Proxy IP is local/private: $proxy_ip" >&2
        exit 1
        ;;
      *)
        ;;
    esac

    geo_json=$(${pkgs.curl}/bin/curl \
      --connect-timeout 3 \
      --max-time 8 \
      --silent \
      --show-error \
      --fail \
      --proxy "socks5h://$addr:$port" \
      "http://ip-api.com/json/?fields=query,countryCode,status" 2>/dev/null || true)

    if [ -z "$geo_json" ]; then
      echo "Geo lookup failed through proxy for $addr:$port" >&2
      exit 1
    fi

    country_code=$(printf '%s' "$geo_json" | grep -o '"countryCode":"[^"]*"' | head -n 1 | cut -d '"' -f 4 || true)
    if [ "$country_code" != "CN" ]; then
      echo "Proxy returned non-China egress: $proxy_ip (country=$country_code)" >&2
      exit 1
    fi

    exit 0
  '';

  # Sanitize a node name for use as a systemd unit name or HAProxy server name.
  # Replaces dots with underscores so "surface.mag" → "surface_mag".
  safeName = node: lib.replaceStrings [ "." ] [ "_" ] node;

  # Pair each node with its index (0-based) for consistent port allocation.
  # Result: [ { node = "surface.mag"; name = "surface_mag"; i = 0; port = 1001; } ... ]
  nodeEntries = lib.imap0 (i: node: {
    inherit node i;
    name = safeName node;
    port = cfg.basePort + i;
  }) cfg.exitNodes;

  mkTailscaledService = entry: {
    description = "Tailscale userspace proxy for ${entry.node}";
    after = [ "network.target" ];
    # Bind to the pool target so it starts/stops with it
    partOf = [ "tailscale-proxy-pool.target" ];
    wantedBy = [ "tailscale-proxy-pool.target" ];

    serviceConfig = {
      Type = "notify";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/lib/tailscale-${entry.name}";
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.tailscale}/bin/tailscaled"
        "--tun=userspace-networking"
        "--socks5-server=127.0.0.1:${toString entry.port}"
        "--socket=/run/tailscale-${entry.name}.sock"
        "--statedir=/var/lib/tailscale-${entry.name}"
        "--port=0"
      ];
      Restart = "always";
      RestartSec = "5s";
    };
  };

  mkTailscaleSetupService = entry: {
    description = "Lazy Tailscale exit node setup for ${entry.node}";
    after = [
      "sops-install-secrets.service"
      "tailscaled-${entry.name}.service"
      "network-online.target"
    ];
    requires = [
      "sops-install-secrets.service"
      "tailscaled-${entry.name}.service"
    ];
    wants = [ "network-online.target" ];
    partOf = [ "tailscale-proxy-pool.target" ];
    wantedBy = [ "tailscale-proxy-pool.target" ];
    path = [
      pkgs.tailscale
      pkgs.jq
      pkgs.coreutils
      pkgs.bash
    ];
    script = ''
      set -u
      login_server=https://ts.${config.networking.domain}
      preauth_key=${config.sops.secrets.tailscale_preauth_key.path}
      socket=/run/tailscale-${entry.name}.sock
      node_name="${entry.node}"

      while true; do
        if [ ! -s "$preauth_key" ]; then
          echo "Tailscale preauth key is not available yet, retrying in 10s..."
          sleep 10
          continue
        fi

        if ! tailscale --socket="$socket" status --json >/dev/null 2>&1; then
          echo "tailscaled socket for $node_name is not ready yet, retrying in 5s..."
          sleep 5
          continue
        fi

        status_json=$(tailscale --socket="$socket" status --json 2>/dev/null || true)
        status=$(printf '%s' "$status_json" | jq -r '.BackendState // "Unknown"' 2>/dev/null || echo Unknown)

        if [ "$status" != "Running" ]; then
          echo "Logging in proxy $node_name..."
          timeout 2m tailscale --socket="$socket" up \
            --reset \
            --login-server "$login_server" \
            --auth-key "file:$preauth_key" \
            --accept-routes=false \
            --advertise-exit-node || echo "Login attempt failed for $node_name, retrying."
          sleep 5
          continue
        fi

        # Do not advertise exit-node on the same socket that is also configured to use one.
        # The remote peer machine should advertise exit-node on its own daemon; the local
        # proxy socket must only consume a remote exit-node.
        exit_node_ip=$(tailscale --socket="$socket" status --json 2>/dev/null \
          | jq -r --arg name "$node_name" '
              .Peer[]
              | select(
                  .HostName == $name
                  or .DNSName == ($name + ".")
                  or (.DNSName | startswith($name + "."))
                )
              | .TailscaleIPs[0]
            ' 2>/dev/null | head -1 || true)

        if [ -z "$exit_node_ip" ]; then
          echo "Exit node $node_name is not online yet or not visible in Tailscale; retrying in 30s..."
          sleep 30
          continue
        fi

        echo "Configuring proxy $node_name to use exit node $exit_node_ip (forced up) ..."

        # Run 'tailscale up' and capture output for debugging.
        echo "Running: tailscale --socket=$socket up --reset --exit-node=$exit_node_ip"
        if ! timeout 2m sh -c "tailscale --socket=$socket up --reset --login-server='$login_server' --auth-key='file:$preauth_key' --accept-routes=false --exit-node='$exit_node_ip' --exit-node-allow-lan-access=false 2>&1 | sed -n '1,200p'"; then
          echo "tailscale up command failed for $node_name"
        fi

        # Also try setting prefs explicitly and capture output.
        echo "Running: tailscale --socket=$socket set --exit-node=$exit_node_ip --exit-node-allow-lan-access=false"
        if ! timeout 30 sh -c "tailscale --socket=$socket set --exit-node='$exit_node_ip' --exit-node-allow-lan-access=false 2>&1 | sed -n '1,200p'"; then
          echo "tailscale set command failed for $node_name"
        fi

        # Wait a short while and then verify the exit-node is in effect and log status.
        for _ in $(seq 1 12); do
          sel=$(tailscale --socket="$socket" status --json 2>/dev/null || true)
          echo "Status JSON for $node_name: $(printf '%s' "$sel" | sed -n '1,200p')"
          ip=$(printf '%s' "$sel" | jq -r '.ExitNodeStatus.TailscaleIPs[0] // empty' 2>/dev/null || true)
          id=$(printf '%s' "$sel" | jq -r '.ExitNodeStatus.ID // empty' 2>/dev/null || true)
          prefs=$(printf '%s' "$sel" | jq -r '.Prefs // empty' 2>/dev/null || true)
          echo "Detected ExitNodeIP=$ip ExitNode=$id Prefs=$prefs"
          if [ -n "$ip" ]; then
            echo "Proxy $node_name now using exit-node $ip"
            break
          fi
          sleep 5
        done

        sleep 10
      done
    '';
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "15s";
      TimeoutStartSec = "3m";
    };
  };

in
{
  options.services.tailscale-proxy-pool = {
    enable = lib.mkEnableOption "Tailscale Proxy Pool via HAProxy";

    exitNodes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        List of Tailscale peer hostnames (Magic DNS short names or FQDNs)
        to use as exit nodes. Each entry gets its own tailscaled instance
        and SOCKS5 port, starting at basePort. HAProxy load-balances across
        all healthy entries on poolPort.

        Example: [ "surface.mag" "arx8.mag" "shg0.mag" ]
      '';
    };

    basePort = lib.mkOption {
      type = lib.types.port;
      default = 1001;
      description = ''
        Starting port for per-node SOCKS5 proxies.
        Node i (0-indexed) listens on basePort + i.
      '';
    };

    poolPort = lib.mkOption {
      type = lib.types.port;
      default = 10080;
      description = "HAProxy load-balanced SOCKS5 pool port.";
    };
  };

  config = lib.mkIf cfg.enable {
    # A dedicated target that groups all proxy daemons.
    # nixos-rebuild switch will start this target (via multi-user.target),
    # which in turn pulls in all the per-node services.
    systemd.targets.tailscale-proxy-pool = {
      description = "Tailscale proxy pool (all exit nodes)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
    };

    # Dynamically generate one tailscaled + one setup service per exit node.
    systemd.services = lib.listToAttrs (
      builtins.concatLists (
        map (entry: [
          (lib.nameValuePair "tailscaled-${entry.name}" (mkTailscaledService entry))
          (lib.nameValuePair "tailscale-setup-${entry.name}" (mkTailscaleSetupService entry))
        ]) nodeEntries
      )
    );

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

        frontend socks5_front
          bind 127.0.0.1:${toString cfg.poolPort}
          default_backend socks5_back

        backend socks5_back
          balance roundrobin
          option external-check
          external-check command ${socks5HealthCheck}
          default-server inter 30s fall 2 rise 1
          ${lib.concatStringsSep "\n          " (
            map (entry: "server proxy_${entry.name} 127.0.0.1:${toString entry.port} check") nodeEntries
          )}
      '';
    };

    # nixos-rebuild switch does not auto-start newly created target units on an
    # already-booted system. This activation script ensures the target (and all
    # per-node services it pulls in) is started/restarted after every switch.
    system.activationScripts.tailscaleProxyPool = {
      supportsDryActivation = false;
      text = ''
        if [ -d /run/systemd/system ]; then
          /run/current-system/sw/bin/systemctl start tailscale-proxy-pool.target || true
        fi
      '';
    };
  };
}
