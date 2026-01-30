# Prowlarr Auto-Configuration
# Automatically configures Prowlarr with API key and basic settings
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.prowlarr;
  prowlarrDataDir = "/var/lib/prowlarr";
  prowlarrPort = config.ports.prowlarr;
in
{
  config = lib.mkIf cfg.enable {
    # Prowlarr initialization service
    systemd.services.prowlarr-auto-config = {
      description = "Auto-configure Prowlarr";
      wantedBy = [ "multi-user.target" ];
      after = [ "prowlarr.service" ];
      requires = [ "prowlarr.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "prowlarr";
        Group = "prowlarr";
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

        PROWLARR_URL="http://localhost:${toString prowlarrPort}"
        DATA_DIR="${prowlarrDataDir}"
        CONFIG_FILE="$DATA_DIR/config.xml"
        MARKER_FILE="$DATA_DIR/.auto-configured"
        PASSWORD_FILE="${config.sops.secrets."password".path}"
        API_KEY_FILE="${config.sops.secrets."media/prowlarr_api_key".path}"

        # Check if already configured
        if [ -f "$MARKER_FILE" ]; then
          echo "Prowlarr already configured, skipping..."
          exit 0
        fi

        # Wait for Prowlarr to create config file
        echo "Waiting for Prowlarr to initialize..."
        for i in {1..60}; do
          if [ -f "$CONFIG_FILE" ]; then
            break
          fi
          sleep 2
        done

        if [ ! -f "$CONFIG_FILE" ]; then
          echo "Prowlarr config file not found, waiting for service to initialize..."
          exit 0
        fi

        echo "Configuring Prowlarr..."

        # Stop Prowlarr to modify config
        systemctl stop prowlarr.service || true
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

        # Restart Prowlarr
        systemctl start prowlarr.service

        # Mark as configured
        touch "$MARKER_FILE"

        echo "Prowlarr auto-configuration complete!"
      '';
    };
  };
}
