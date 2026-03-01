{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.frp-panel.client;
in
{
  options.services.frp-panel.client = {
    enable = mkEnableOption "frp-panel client";
    package = mkOption {
      type = types.package;
      default = pkgs.frp-panel;
    };
    masterAddress = mkOption {
      type = types.str;
      description = "Master address (hostname or IP)";
    };
    masterRpcPort = mkOption {
      type = types.port;
      default = 5000;
    };
    joinToken = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Token for automatic registration. If set, node will auto-join as ephemeral.";
    };
    clientId = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Client ID (optional if using joinToken)";
    };
    clientSecret = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Client Secret (optional if using joinToken)";
    };
  };

  config = mkIf cfg.enable {
    # Automatically define the secret if joinToken is using sops placeholder
    sops.secrets."frp_panel/join_token" = mkIf (
      cfg.joinToken != null
      && (builtins.isString cfg.joinToken && lib.strings.hasInfix "placeholder" cfg.joinToken)
    ) { };

    systemd.services.frp-panel-client = {
      description = "frp-panel client service";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
        iproute2
        wireguard-tools
        coreutils
      ]; # Needed for networking setup
      serviceConfig = {
        StateDirectory = "frp-panel";
        WorkingDirectory = "/var/lib/frp-panel";
        # Map the hardcoded /etc/frpp/.env to a writable location in StateDirectory
        BindPaths = [ "/var/lib/frp-panel/etc:/etc/frpp" ];

        # Use '-' to skip if file doesn't exist yet
        EnvironmentFile = [ "-/var/lib/frp-panel/etc/.env" ];

        ExecStartPre = mkIf (cfg.joinToken != null) (
          pkgs.writeShellScript "frp-panel-join" ''
            if [ ! -f /var/lib/frp-panel/etc/.env ]; then
              echo "Registering ephemeral client with token..."
              mkdir -p /var/lib/frp-panel/etc
              # Run join within the same namespace or just ensure the target exists
              ${cfg.package}/bin/frp-panel join \
                --join-token "${cfg.joinToken}" \
                --api-url "https://${cfg.masterAddress}" \
                --rpc-url "grpc://${cfg.masterAddress}:${toString cfg.masterRpcPort}"
            fi
          ''
        );

        ExecStart = "${cfg.package}/bin/frp-panel client";
        Restart = "always";
        Environment = [
          "GIN_MODE=release"
          # These can be fallbacks if .env is missing or for initial join
          "CLIENT_API_URL=https://${cfg.masterAddress}"
          "CLIENT_RPC_URL=grpc://${cfg.masterAddress}:${toString cfg.masterRpcPort}"
        ]
        ++ (lib.optional (cfg.clientId != null) "CLIENT_ID=${cfg.clientId}")
        ++ (lib.optional (cfg.clientSecret != null) "CLIENT_SECRET=${cfg.clientSecret}");

        # WireGuard needs some privileges
        CapabilityBoundingSet = "CAP_NET_ADMIN CAP_NET_RAW";
        AmbientCapabilities = "CAP_NET_ADMIN CAP_NET_RAW";
      };
    };
  };
}
