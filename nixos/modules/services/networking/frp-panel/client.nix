{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.frp-panel.client;
  clientEnv = ''
    GIN_MODE=release
    CLIENT_API_URL=http://${cfg.masterAddress}:${toString cfg.masterApiPort}
    CLIENT_RPC_URL=grpc://${cfg.masterAddress}:${toString cfg.masterRpcPort}
  ''
  + lib.optionalString (cfg.clientId != null) ''
    CLIENT_ID=${cfg.clientId}
  ''
  + lib.optionalString (cfg.clientSecret != null) ''
    CLIENT_SECRET=${cfg.clientSecret}
  '';
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
      default = 15000;
    };
    masterApiPort = mkOption {
      type = types.port;
      default = 18080;
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
    sops.secrets."frp_panel/join_token" = mkIf (cfg.joinToken != null) { };
    sops.secrets."frp_panel/client_id" = { };
    sops.secrets."frp_panel/client_secret" = { };
    sops.templates."frp-panel-client.env".content = clientEnv;

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
        EnvironmentFile = config.sops.templates."frp-panel-client.env".path;

        ExecStartPre = mkIf (cfg.joinToken != null) (
          pkgs.writeShellScript "frp-panel-join" ''
            if [ ! -f /var/lib/frp-panel/etc/.env ]; then
              echo "Registering ephemeral client with token..."
              mkdir -p /var/lib/frp-panel/etc
              # Run join within the same namespace or just ensure the target exists
              ${cfg.package}/bin/frp-panel join \
                --join-token "${cfg.joinToken}" \
                --api-url "http://${cfg.masterAddress}:${toString cfg.masterApiPort}" \
                --rpc-url "grpc://${cfg.masterAddress}:${toString cfg.masterRpcPort}"
            fi
          ''
        );

        ExecStart = "${cfg.package}/bin/frp-panel client";
        Restart = "always";

        # WireGuard needs some privileges
        CapabilityBoundingSet = "CAP_NET_ADMIN CAP_NET_RAW";
        AmbientCapabilities = "CAP_NET_ADMIN CAP_NET_RAW";
      };
    };
  };
}
