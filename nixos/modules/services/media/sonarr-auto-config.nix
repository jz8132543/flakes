# Sonarr Auto-Configuration
# Automatically configures Sonarr with API key and basic settings
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.sonarr;
  sonarrDataDir = cfg.dataDir;
  sonarrPort = config.ports.sonarr;
in
{
  config = lib.mkIf cfg.enable {
    # Sonarr initialization service
    systemd.services.sonarr-auto-config = {
      description = "Auto-configure Sonarr";
      wantedBy = [ "multi-user.target" ];
      after = [ "sonarr.service" ];
      wants = [ "sonarr.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Run as root to be able to restart sonarr service
      };

      path = with pkgs; [
        curl
        jq
        coreutils
        sqlite
        xmlstarlet
      ];

      script = ''
        set -euo pipefail

        SONARR_URL="http://localhost:${toString sonarrPort}"
        DATA_DIR="${sonarrDataDir}"
        CONFIG_FILE="$DATA_DIR/config.xml"
        DB_FILE="$DATA_DIR/sonarr.db"
        MARKER_FILE="$DATA_DIR/.auto-configured"
        PASSWORD_FILE="${config.sops.secrets."password".path}"
        API_KEY_FILE="${config.sops.secrets."media/sonarr_api_key".path}"

        # Check if already configured
        if [ -f "$MARKER_FILE" ]; then
          echo "Sonarr already configured, skipping..."
          exit 0
        fi

        # Wait for Sonarr to create config file
        echo "Waiting for Sonarr to initialize..."
        for i in {1..60}; do
          if [ -f "$CONFIG_FILE" ]; then
            break
          fi
          sleep 2
        done

        if [ ! -f "$CONFIG_FILE" ]; then
          echo "Sonarr config file not found, waiting for service to initialize..."
          exit 0
        fi

        echo "Configuring Sonarr..."

        # Stop Sonarr to modify config
        systemctl stop sonarr.service || true
        sleep 2

        # Read API key from sops (if available) or keep generated one
        if [ -f "$API_KEY_FILE" ]; then
          API_KEY=$(cat "$API_KEY_FILE")
          # Update API key in config.xml
          xmlstarlet ed -L -u "/Config/ApiKey" -v "$API_KEY" "$CONFIG_FILE" 2>/dev/null || true
        fi

        # Enable authentication
        xmlstarlet ed -L \
          -u "/Config/AuthenticationMethod" -v "Forms" \
          -u "/Config/AuthenticationRequired" -v "Enabled" \
          "$CONFIG_FILE" 2>/dev/null || true

        # Add missing config elements if they don't exist
        if ! grep -q "<AuthenticationMethod>" "$CONFIG_FILE"; then
          xmlstarlet ed -L -s "/Config" -t elem -n "AuthenticationMethod" -v "Forms" "$CONFIG_FILE" || true
        fi
        if ! grep -q "<AuthenticationRequired>" "$CONFIG_FILE"; then
          xmlstarlet ed -L -s "/Config" -t elem -n "AuthenticationRequired" -v "Enabled" "$CONFIG_FILE" || true
        fi

        # Restart Sonarr
        systemctl start sonarr.service
        sleep 5

        # Wait for Sonarr API to be ready
        API_KEY=$(xmlstarlet sel -t -v "/Config/ApiKey" "$CONFIG_FILE" 2>/dev/null || echo "")
        if [ -z "$API_KEY" ]; then
          echo "No API key found in config"
          exit 0
        fi

        for i in {1..30}; do
          if curl -sf "$SONARR_URL/api/v3/system/status" -H "X-Api-Key: $API_KEY" >/dev/null 2>&1; then
            break
          fi
          sleep 2
        done

        # Read password
        if [ -f "$PASSWORD_FILE" ]; then
          PASSWORD=$(cat "$PASSWORD_FILE")
        else
          PASSWORD="changeme"
        fi

        # Check if root folder exists
        ROOT_FOLDERS=$(curl -sf "$SONARR_URL/api/v3/rootfolder" -H "X-Api-Key: $API_KEY" 2>/dev/null || echo "[]")
        HAS_ROOT=$(echo "$ROOT_FOLDERS" | jq 'length > 0')

        if [ "$HAS_ROOT" = "false" ]; then
          echo "Adding root folder..."
          curl -sf -X POST "$SONARR_URL/api/v3/rootfolder" \
            -H "X-Api-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            -d '{"path": "/srv/media/tv"}' || true
        fi

        # Mark as configured
        touch "$MARKER_FILE"

        echo "Sonarr auto-configuration complete!"
        echo "API Key: $API_KEY"
      '';
    };
  };
}
