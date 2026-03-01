{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.frp-panel.master;
in
{
  options.services.frp-panel.master = {
    enable = mkEnableOption "frp-panel master";
    package = mkOption {
      type = types.package;
      default = pkgs.frp-panel;
    };
    appId = mkOption {
      type = types.str;
      description = "Application ID for frp-panel";
    };
    globalSecret = mkOption {
      type = types.str;
      description = "Global Secret for frp-panel (App.GlobalSecret)";
    };
    masterSecret = mkOption {
      type = types.str;
      description = "Master Secret for frp-panel";
    };
    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
    };
    grpcPort = mkOption {
      type = types.port;
      default = 5000;
    };
    extraConfig = mkOption {
      type = types.attrs;
      default = { };
    };
  };

  config = mkIf cfg.enable {
    # Automatically define secrets if using sops placeholders
    sops.secrets."frp_panel/app_id" = mkIf (
      builtins.isString cfg.appId && lib.strings.hasInfix "placeholder" cfg.appId
    ) { };
    sops.secrets."frp_panel/global_secret" = mkIf (
      builtins.isString cfg.globalSecret && lib.strings.hasInfix "placeholder" cfg.globalSecret
    ) { };

    systemd.services.frp-panel-master = {
      description = "frp-panel master service";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        StateDirectory = "frp-panel";
        ExecStart = "${cfg.package}/bin/frp-panel master";
        Restart = "always";
        Environment = [
          "APP_GLOBAL_SECRET=${cfg.globalSecret}"
          "MASTER_API_PORT=${toString cfg.port}"
          "MASTER_RPC_PORT=${toString cfg.grpcPort}"
          "MASTER_RPC_HOST=${cfg.host}"
          "DB_TYPE=sqlite3"
          "DB_DSN=/var/lib/frp-panel/data.db?_pragma=journal_mode(WAL)"
          "GIN_MODE=release"
        ];
      };
    };

    systemd.services.frp-panel-cleanup = {
      description = "Cleanup inactive ephemeral frp-panel nodes";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "frp-panel-cleanup" ''
          DB_PATH="/var/lib/frp-panel/data.db"
          if [ -f "$DB_PATH" ]; then
             # Delete clients where ephemeral=1 and last_seen is older than 7 days
             ${pkgs.sqlite}/bin/sqlite3 "$DB_PATH" "DELETE FROM clients WHERE ephemeral = 1 AND (last_seen_at < datetime('now', '-7 days') OR (last_seen_at IS NULL AND created_at < datetime('now', '-1 day')));"
          fi
        '';
      };
    };

    systemd.timers.frp-panel-cleanup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    networking.firewall.allowedTCPPorts = [
      cfg.port
      cfg.grpcPort
    ];
  };
}
