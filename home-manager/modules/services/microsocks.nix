{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.microsocks;
in
{
  options.services.microsocks = {
    enable = lib.mkEnableOption "microsocks SOCKS5 server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.microsocks;
      description = "The package to use for microsocks.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 1080;
      description = "The port to listen on.";
    };

    bindAddr = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "The address to bind to. Ignored if bindInterface is set.";
    };

    bindInterface = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "tailscale0";
      description = "The interface to bind to. If set, bindAddr is ignored.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra arguments to pass to microsocks.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.microsocks = {
      Unit = {
        Description = "microsocks SOCKS5 server";
        After = [ "network.target" ];
      };

      Service = {
        ExecStart =
          let
            startScript = pkgs.writeShellScript "microsocks-start" ''
              set -e
              ${
                if cfg.bindInterface != null then
                  ''
                    # Auto-find IP for interface ${cfg.bindInterface}
                    BIND_IP=$(${pkgs.iproute2}/bin/ip -4 addr show "${cfg.bindInterface}" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1 || true)
                    if [ -z "$BIND_IP" ]; then
                      echo "Error: Could not find IPv4 for interface ${cfg.bindInterface}"
                      exit 1
                    fi
                    echo "Auto-discovered IP $BIND_IP on ${cfg.bindInterface}"
                  ''
                else
                  ''
                    # Use explicit bind address
                    BIND_IP="${cfg.bindAddr}"
                    echo "Using explicit bind address $BIND_IP"
                  ''
              }
              exec ${cfg.package}/bin/microsocks -p ${toString cfg.port} -i "$BIND_IP" ${lib.escapeShellArgs cfg.extraArgs}
            '';
          in
          "${startScript}";
        Restart = "on-failure";
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
