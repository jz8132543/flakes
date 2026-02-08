{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  cfg = config.services.derp;
in
{
  options.services.derp = {
    enable = lib.mkEnableOption "Tailscale DERP relay server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.tailscale;
      description = "The package to use for the DERP relay.";
    };

    hostname = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = "The hostname to use for the DERP relay.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 10043;
      description = "The port to listen on.";
    };

    stunPort = lib.mkOption {
      type = lib.types.port;
      default = 3440;
      description = "The STUN port to listen on.";
    };

    certMode = lib.mkOption {
      type = lib.types.enum [
        "letsencrypt"
        "manual"
      ];
      default = "manual";
      description = "Certificate mode for derper.";
    };

    certDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/derper/certs";
      description = "Directory where certificates are stored.";
    };

    verifyClients = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to verify clients.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra arguments to pass to derper.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.tailscale ];
    # Ensure cert directory exists
    systemd.user.services.derp = {
      Unit = {
        Description = "Tailscale DERP Relay Server";
        After = [
          "network.target"
          "acme-main.service"
        ];
        Wants = [ "acme-main.service" ];
      };

      Service = {
        # Create necessary directories
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${cfg.certDir}";
        ExecStart =
          let
            args = [
              "-hostname ${cfg.hostname}"
              "-a :${toString cfg.port}"
              "-stun-port ${toString cfg.stunPort}"
              "-http-port -1"
              "-certmode ${cfg.certMode}"
              "-certdir ${cfg.certDir}"
              "-c ${config.home.homeDirectory}/.config/derper/derper.conf"
            ]
            ++ lib.optional cfg.verifyClients "-verify-clients"
            ++ cfg.extraArgs;
          in
          "${osConfig.pkgs.tailscale}/bin/derp ${builtins.concatStringsSep " " args}";
        Restart = "on-failure";
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
