{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.tailscale-proxy-pool;

  mkTailscaledService = node: port: {
    description = "Tailscale proxy for ${node}";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "notify";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/lib/tailscale-${node}";
      ExecStart = "${pkgs.tailscale}/bin/tailscaled --tun=userspace-networking --socks5-server=127.0.0.1:${toString port} --socket=/run/tailscale-${node}.sock --statedir=/var/lib/tailscale-${node} --port=0";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  mkTailscaleSetupService = node: {
    description = "Tailscale automatic login for proxy ${node}";
    after = [
      "sops-nix.service"
      "tailscaled-${node}.service"
      "network-online.target"
    ];
    requires = [
      "sops-nix.service"
      "tailscaled-${node}.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.tailscale
      pkgs.jq
      pkgs.coreutils
    ];
    script = ''
      login_server=https://ts.''${config.networking.domain}
      preauth_key=''${config.sops.secrets.tailscale_preauth_key.path}
      socket=/run/tailscale-${node}.sock

      for _ in $(seq 1 60); do
        if [ -s "$preauth_key" ] && tailscale --socket=$socket status --json >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done

      if [ ! -s "$preauth_key" ]; then
        echo "Tailscale preauth key is not available"
        exit 1
      fi

      status_json=$(tailscale --socket=$socket status --json 2>/dev/null || true)
      status=$(printf '%s' "$status_json" | jq -r '.BackendState // "Unknown"' 2>/dev/null || echo Unknown)
      if [ "$status" = "Running" ]; then
        echo "Tailscale proxy ${node} is already running."
        exit 0
      fi

      echo "Logging in proxy ${node}..."
      timeout 2m tailscale --socket=$socket up \
        --reset \
        --login-server "$login_server" \
        --auth-key "file:''${config.sops.secrets.tailscale_preauth_key.path}" \
        --exit-node=${node} \
        --exit-node-allow-lan-access \
        --accept-routes=false
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "10";
      TimeoutStartSec = "3m";
    };
  };

in
{
  options.services.tailscale-proxy-pool = {
    enable = lib.mkEnableOption "Tailscale Proxy Pool via HAProxy";

    exitNodes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "surface"
        "arx8"
        "shg0"
      ];
      description = "List of Tailscale machine names to use as exit nodes.";
    };

    basePort = lib.mkOption {
      type = lib.types.port;
      default = 1001;
      description = "Starting port for local SOCKS5 proxies.";
    };

    poolPort = lib.mkOption {
      type = lib.types.port;
      default = 10080;
      description = "HAProxy port providing the load-balanced SOCKS5 pool.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services = lib.listToAttrs (
      builtins.concatLists (
        lib.imap0 (i: node: [
          (lib.nameValuePair "tailscaled-${node}" (mkTailscaledService node (cfg.basePort + i)))
          (lib.nameValuePair "tailscale-setup-${node}" (mkTailscaleSetupService node))
        ]) cfg.exitNodes
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
          option tcp-check
          ${lib.concatImapStringsSep "\n          " (
            i: node: "server proxy_${node} 127.0.0.1:${toString (cfg.basePort + i)} check"
          ) cfg.exitNodes}
      '';
    };
  };
}
