# Jellyfin Auto-Configuration
# Automatically configures Jellyfin with predefined credentials and settings
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.jellyfin;
  jellyfinDataDir = cfg.dataDir;

  # Default media libraries configuration
in
{
  config = lib.mkIf cfg.enable {
    # Jellyfin initialization service
    systemd.services.jellyfin-auto-config = {
      description = "Auto-configure Jellyfin";
      wantedBy = [ "multi-user.target" ];
      after = [ "jellyfin.service" ];
      requires = [ "jellyfin.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Run as root to access sops secrets
      };

      path = with pkgs; [
        curl
        jq
        coreutils
        gnused
        openssl
      ];

      script = ''
        set -euo pipefail

        JELLYFIN_URL="http://localhost:${toString config.ports.jellyfin}"
        DATA_DIR="${jellyfinDataDir}"
        CONFIG_DIR="$DATA_DIR/config"
        MARKER_FILE="$CONFIG_DIR/.auto-configured"
        PASSWORD_FILE="${config.sops.secrets."password".path}"

        # Check if already configured
        if [ -f "$MARKER_FILE" ]; then
          echo "Jellyfin already configured, skipping..."
          exit 0
        fi

        # Wait for Jellyfin to be ready
        echo "Waiting for Jellyfin to start..."
        for i in {1..60}; do
          if curl -sf "$JELLYFIN_URL/System/Ping" >/dev/null 2>&1; then
            break
          fi
          sleep 2
        done

        # Check if startup wizard is needed
        STARTUP_CONFIG=$(curl -sf "$JELLYFIN_URL/Startup/Configuration" 2>/dev/null || echo "{}")
        IS_COMPLETE=$(echo "$STARTUP_CONFIG" | jq -r '.IsStartupWizardCompleted // false')

        if [ "$IS_COMPLETE" = "true" ]; then
          echo "Jellyfin startup wizard already completed"
          touch "$MARKER_FILE"
          exit 0
        fi

        echo "Running Jellyfin initial setup..."

        # Read password from sops
        if [ -f "$PASSWORD_FILE" ]; then
          PASSWORD=$(cat "$PASSWORD_FILE")
        else
          echo "Password file not found, using default"
          PASSWORD="changeme"
        fi

        # Step 1: Set startup configuration
        curl -sf -X POST "$JELLYFIN_URL/Startup/Configuration" \
          -H "Content-Type: application/json" \
          -d '{
            "UICulture": "zh-CN",
            "MetadataCountryCode": "CN",
            "PreferredMetadataLanguage": "zh"
          }' || true

        # Step 2: Create admin user
        curl -sf -X POST "$JELLYFIN_URL/Startup/User" \
          -H "Content-Type: application/json" \
          -d "{
            \"Name\": \"i\",
            \"Password\": \"$PASSWORD\"
          }" || true

        # Step 3: Set remote access
        curl -sf -X POST "$JELLYFIN_URL/Startup/RemoteAccess" \
          -H "Content-Type: application/json" \
          -d '{
            "EnableRemoteAccess": true,
            "EnableAutomaticPortMapping": false
          }' || true

        # Step 4: Complete startup wizard
        curl -sf -X POST "$JELLYFIN_URL/Startup/Complete" || true

        echo "Jellyfin initial setup complete!"

        # Authenticate to get access token for further configuration
        echo "Authenticating as admin user..."
        AUTH_RESULT=$(curl -sf -X POST "$JELLYFIN_URL/Users/AuthenticateByName" \
          -H "Content-Type: application/json" \
          -H "X-Emby-Authorization: MediaBrowser Client=\"Automation\", Device=\"NixOS\", DeviceId=\"auto-config\", Version=\"1.0.0\"" \
          -d "{
            \"Username\": \"i\",
            \"Pw\": \"$PASSWORD\"
          }" 2>/dev/null || echo "{}")

        ACCESS_TOKEN=$(echo "$AUTH_RESULT" | jq -r '.AccessToken // empty')
        USER_ID=$(echo "$AUTH_RESULT" | jq -r '.User.Id // empty')

        if [ -z "$ACCESS_TOKEN" ]; then
          echo "Failed to authenticate, will configure on next run"
          exit 0
        fi

        AUTH_HEADER="X-Emby-Token: $ACCESS_TOKEN"

        # Create media libraries (this may require API interaction)
        echo "Note: Media libraries should be added via web UI or Terraform"

        # Mark as configured
        mkdir -p "$CONFIG_DIR"
        touch "$MARKER_FILE"

        echo "Jellyfin auto-configuration complete!"
        echo ""
        echo "Access Jellyfin at: https://jellyfin.${config.networking.domain}"
        echo "Username: i"
        echo "Password: (from sops secret 'password')"
      '';
    };
  };
}
