# Radarr Auto-Configuration
# Automatically configures Radarr with API key and basic settings
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.radarr;
  radarrDataDir = cfg.dataDir;
  radarrPort = config.ports.radarr;
in
{
  config = lib.mkIf cfg.enable {
    # Radarr initialization service
    systemd.services.radarr-auto-config = {
      description = "Auto-configure Radarr";
      wantedBy = [ "multi-user.target" ];
      after = [ "radarr.service" ];
      wants = [ "radarr.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Run as root to be able to restart radarr service
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

        RADARR_URL="http://localhost:${toString radarrPort}"
        DATA_DIR="${radarrDataDir}"
        CONFIG_FILE="$DATA_DIR/config.xml"
        MARKER_FILE="$DATA_DIR/.auto-configured"
        PASSWORD_FILE="${config.sops.secrets."password".path}"
        API_KEY_FILE="${config.sops.secrets."media/radarr_api_key".path}"

        # Check if already configured
        if [ -f "$MARKER_FILE" ]; then
          echo "Radarr already configured, skipping..."
          exit 0
        fi

        # Wait for Radarr to create config file
        echo "Waiting for Radarr to initialize..."
        for i in {1..60}; do
          if [ -f "$CONFIG_FILE" ]; then
            break
          fi
          sleep 2
        done

        if [ ! -f "$CONFIG_FILE" ]; then
          echo "Radarr config file not found, waiting for service to initialize..."
          exit 0
        fi

        echo "Configuring Radarr..."

        # Stop Radarr to modify config
        systemctl stop radarr.service || true
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

        # Restart Radarr
        systemctl start radarr.service
        sleep 5

        # Wait for Radarr API to be ready
        API_KEY=$(xmlstarlet sel -t -v "/Config/ApiKey" "$CONFIG_FILE" 2>/dev/null || echo "")
        if [ -z "$API_KEY" ]; then
          echo "No API key found in config"
          exit 0
        fi

        for i in {1..30}; do
          if curl -sf "$RADARR_URL/api/v3/system/status" -H "X-Api-Key: $API_KEY" >/dev/null 2>&1; then
            break
          fi
          sleep 2
        done

        # Check if root folder exists
        ROOT_FOLDERS=$(curl -sf "$RADARR_URL/api/v3/rootfolder" -H "X-Api-Key: $API_KEY" 2>/dev/null || echo "[]")
        HAS_ROOT=$(echo "$ROOT_FOLDERS" | jq 'length > 0')

        if [ "$HAS_ROOT" = "false" ]; then
          echo "Adding root folder..."
          curl -sf -X POST "$RADARR_URL/api/v3/rootfolder" \
            -H "X-Api-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            -d '{"path": "/srv/media/movies"}' || true
        fi

        # Mark as configured
        touch "$MARKER_FILE"

        echo "Radarr auto-configuration complete!"
        echo "API Key: $API_KEY"
      '';
    };
  };
}
