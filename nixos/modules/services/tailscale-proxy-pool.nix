{
  config,
  lib,
  ...
}:

let
  cfg = config.services.tailscale-proxy-pool;
  safeName = node: lib.replaceStrings [ "." ] [ "_" ] node;
in
{
  options.services.tailscale-proxy-pool = {
    enable = lib.mkEnableOption "Tailscale HAProxy SOCKS5 proxy pool";

    exitNodes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Tailscale Magic DNS names to use as SOCKS5 backend servers.";
    };

    poolPort = lib.mkOption {
      type = lib.types.port;
      default = 10080;
      description = "HAProxy load-balanced SOCKS5 pool port (on localhost).";
    };

    remotePort = lib.mkOption {
      type = lib.types.port;
      default = 1080;
      description = "Port each remote SOCKS5 server is listening on.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.haproxy = {
      enable = true;
      config = ''
        global
          log stdout format raw local0
          maxconn 2000
          user haproxy
          group haproxy
          # Use Magic DNS resolver via Tailscale local daemon
          # 100.100.100.100 is the tailscale DNS IP
          resolvers tailscale
            nameserver ts 100.100.100.100:53
            resolve_retries 3
            timeout resolve 2s
            timeout retry 1s
            hold valid 60s

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
          # Native tcp-check will attempt to connect to the remote SOCKS5 port.
          # If the remote machine is offline, the connection will time out or fail.
          default-server inter 10s fall 2 rise 1 resolvers tailscale
          ${lib.concatMapStringsSep "\n          " (
            node: "server proxy_${safeName node} ${node}:${toString cfg.remotePort} check"
          ) cfg.exitNodes}
      '';
    };

    # Automatically reload HAProxy if the config changes
    systemd.services.haproxy.reloadIfChanged = true;
  };
}
