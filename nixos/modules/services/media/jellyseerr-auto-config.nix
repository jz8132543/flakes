# Jellyseerr Auto-Configuration
# Automatically configures Jellyseerr with Jellyfin integration
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.jellyseerr;
  jellyseerrDataDir = "/var/lib/jellyseerr";
  jellyseerrPort = config.ports.jellyseerr;
in
{
  config = lib.mkIf cfg.enable {
    # Jellyseerr initialization service
    systemd.services.jellyseerr-auto-config = {
      description = "Auto-configure Jellyseerr";
      wantedBy = [ "multi-user.target" ];
      after = [
        "jellyseerr.service"
        "jellyfin.service"
        "sonarr.service"
        "radarr.service"
      ];
      requires = [ "jellyseerr.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "jellyseerr";
        Group = "jellyseerr";
      };

      path = with pkgs; [
        curl
        jq
        coreutils
      ];

      script = ''
        set -euo pipefail

        JELLYSEERR_URL="http://localhost:${toString jellyseerrPort}"
        DATA_DIR="${jellyseerrDataDir}"
        DB_FILE="$DATA_DIR/db/db.sqlite3"
        MARKER_FILE="$DATA_DIR/.auto-configured"
        PASSWORD_FILE="${config.sops.secrets."password".path}"
        SONARR_API_KEY_FILE="${config.sops.secrets."media/sonarr_api_key".path}"
        RADARR_API_KEY_FILE="${config.sops.secrets."media/radarr_api_key".path}"

        # Check if already configured
        if [ -f "$MARKER_FILE" ]; then
          echo "Jellyseerr already configured, skipping..."
          exit 0
        fi

        # Wait for Jellyseerr to start
        echo "Waiting for Jellyseerr to initialize..."
        for i in {1..60}; do
          if curl -sf "$JELLYSEERR_URL/api/v1/status" >/dev/null 2>&1; then
            break
          fi
          sleep 2
        done

        # Check if setup is needed
        STATUS=$(curl -sf "$JELLYSEERR_URL/api/v1/status" 2>/dev/null || echo "{}")
        INITIALIZED=$(echo "$STATUS" | jq -r '.initialized // false')

        if [ "$INITIALIZED" = "true" ]; then
          echo "Jellyseerr already initialized"
          touch "$MARKER_FILE"
          exit 0
        fi

        echo "Configuring Jellyseerr..."
        echo "NOTE: Jellyseerr requires manual initial setup via web UI due to complex OAuth flow with Jellyfin."
        echo ""
        echo "Please complete the following steps manually:"
        echo "1. Open https://seerr.${config.networking.domain}"
        echo "2. Select 'Use your Jellyfin account' for login"
        echo "3. Enter Jellyfin URL: http://localhost:${toString config.ports.jellyfin}"
        echo "4. Login with username 'i' and the configured password"
        echo "5. Configure Sonarr and Radarr connections"
        echo ""

        # Read API keys for display
        if [ -f "$SONARR_API_KEY_FILE" ]; then
          SONARR_API_KEY=$(cat "$SONARR_API_KEY_FILE")
          echo "Sonarr API Key: $SONARR_API_KEY"
          echo "Sonarr URL: http://localhost:${toString config.ports.sonarr}"
        fi

        if [ -f "$RADARR_API_KEY_FILE" ]; then
          RADARR_API_KEY=$(cat "$RADARR_API_KEY_FILE")
          echo "Radarr API Key: $RADARR_API_KEY"
          echo "Radarr URL: http://localhost:${toString config.ports.radarr}"
        fi

        # Mark as "attempted" - user must complete manually
        touch "$MARKER_FILE"

        echo ""
        echo "Jellyseerr setup instructions complete!"
      '';
    };
  };
}
