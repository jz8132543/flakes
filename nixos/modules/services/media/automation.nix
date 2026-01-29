{ config, pkgs, ... }:

{
  systemd.services.media-automation = {
    description = "Automate Media Stack Interconnection (Sonarr/Radarr/Prowlarr/Jellyseerr/Jellyfin)";
    after = [
      "sonarr.service"
      "radarr.service"
      "prowlarr.service"
      "jellyseerr.service"
      "jellyfin.service"
    ];
    wants = [
      "sonarr.service"
      "radarr.service"
      "prowlarr.service"
      "jellyseerr.service"
      "jellyfin.service"
    ];
    wantedBy = [ "multi-user.target" ];

    path = with pkgs; [
      xmlstarlet
      sqlite
      curl
      jq
      coreutils
      gnugrep
    ];

    serviceConfig = {
      Type = "oneshot";
      User = "root"; # Needs access to all /var/lib directories
      WorkingDirectory = "/var/lib";
    };

    script = ''
      set -euo pipefail

      echo "Waiting for services to initialize..."
      sleep 10

      # Correct Paths (using /var/lib symlinks which NixOS creates)
      SONARR_CONFIG="/var/lib/sonarr/.config/NzbDrone/config.xml"
      RADARR_CONFIG="/var/lib/radarr/.config/Radarr/config.xml"
      PROWLARR_CONFIG="/var/lib/prowlarr/config.xml"
      QBIT_CONFIG="/var/lib/qbittorrent/qBittorrent/config/qBittorrent.conf"
      JELLYSEERR_SETTINGS="/var/lib/jellyseerr/config/settings.json"
      JELLYFIN_DB="/var/lib/jellyfin/data/jellyfin.db"
      PASSWORD_FILE="${config.sops.secrets."password".path}"
      PASSWORD=$(cat "$PASSWORD_FILE")

      # --- Extract Keys & Set Auth Method ---
      get_xml_key() {
        if [ -f "$1" ]; then
          xmlstarlet sel -t -v "//ApiKey" "$1" || echo ""
        else
          echo ""
        fi
      }

      set_xml_auth() {
        local CONFIG=$1
        if [ -f "$CONFIG" ]; then
          echo "Ensuring native auth (Forms) and username 'i' in $CONFIG"
          # Update or Add Username/AuthenticationMethod
          xmlstarlet ed --inplace --update "//AuthenticationMethod" --value "Forms" "$CONFIG" 2>/dev/null || \
          xmlstarlet ed --inplace --subnode "/Config" --type elem -n AuthenticationMethod -v "Forms" "$CONFIG"
          
          xmlstarlet ed --inplace --update "//Username" --value "i" "$CONFIG" 2>/dev/null || \
          xmlstarlet ed --inplace --subnode "/Config" --type elem -n Username -v "i" "$CONFIG"
        fi
      }

      echo "Extracting API Keys..."
      SONARR_KEY=$(get_xml_key "$SONARR_CONFIG")
      RADARR_KEY=$(get_xml_key "$RADARR_CONFIG")
      PROWLARR_KEY=$(get_xml_key "$PROWLARR_CONFIG")

      set_xml_auth "$SONARR_CONFIG"
      set_xml_auth "$RADARR_CONFIG"
      set_xml_auth "$PROWLARR_CONFIG"

      # --- qBittorrent Config ---
      if [ -f "$QBIT_CONFIG" ]; then
        echo "Updating qBittorrent config..."
        sed -i 's/WebUI\\Username=.*/WebUI\\Username=i/' "$QBIT_CONFIG"
        # We can't easily hash the password here, but we set the username.
      fi

      # --- Jellyfin API Key ---
      AUTO_KEY="automation-api-key-generated-by-nixos"
      if [ -f "$JELLYFIN_DB" ]; then
        EXISTS=$(sqlite3 "$JELLYFIN_DB" "SELECT Id FROM ApiKeys WHERE AccessToken = '$AUTO_KEY';")
        if [ -z "$EXISTS" ]; then
           DATE_NOW=$(date -u +"%Y-%m-%d %H:%M:%S")
           sqlite3 "$JELLYFIN_DB" "INSERT INTO ApiKeys (DateCreated, DateLastActivity, Name, AccessToken) VALUES ('$DATE_NOW', '$DATE_NOW', 'Jellyseerr-Automation', '$AUTO_KEY');"
        fi
      fi

      # --- Jellyseerr Settings (JSON) ---
      if [ -f "$JELLYSEERR_SETTINGS" ]; then
        echo "Declaratively configuring Jellyseerr settings.json..."
        # Stop service to avoid overwrite
        systemctl stop jellyseerr || true
        
        # Build the update object
        jq ".jellyfin.ip = \"127.0.0.1\" | 
            .jellyfin.port = ${toString config.ports.jellyfin} | 
            .jellyfin.apiKey = \"$AUTO_KEY\" | 
            .jellyfin.name = \"Jellyfin\" | 
            .public.initialized = true |
            .main.mediaServerType = 4" "$JELLYSEERR_SETTINGS" > "$JELLYSEERR_SETTINGS.tmp" && mv "$JELLYSEERR_SETTINGS.tmp" "$JELLYSEERR_SETTINGS"
        
        systemctl start jellyseerr || true
      fi

      echo "=========================================="
      echo "      MEDIA STACK AUTOMATION REPORT       "
      echo "=========================================="
      echo "Username:         i"
      echo "Password:         (check sops secret)"
      echo "Sonarr API Key:   $SONARR_KEY"
      echo "Radarr API Key:   $RADARR_KEY"
      echo "Prowlarr API Key: $PROWLARR_KEY"
      echo "Auto connection to Jellyfin initiated."
      echo "=========================================="

      # --- Prowlarr Configuration ---
      if [ -n "$PROWLARR_KEY" ]; then
        add_to_prowlarr() {
          local NAME=$1; local URL=$2; local API_KEY=$3; local CONTRACT=$4
          local EXISTING=$(curl -s -H "X-Api-Key: $PROWLARR_KEY" "http://localhost:${toString config.ports.prowlarr}/api/v1/applications" | jq ".[] | select(.name == \"$NAME\") | .id")
          if [ -z "$EXISTING" ]; then
            curl -s -X POST "http://localhost:${toString config.ports.prowlarr}/api/v1/applications" \
              -H "Content-Type: application/json" \
              -H "X-Api-Key: $PROWLARR_KEY" \
              -d "{\"name\": \"$NAME\", \"implementationName\": \"$NAME\", \"implementation\": \"$NAME\", \"configContract\": \"$CONTRACT\", \"fields\": [{\"name\": \"prowlarrUrl\", \"value\": \"http://localhost:${toString config.ports.prowlarr}\"}, {\"name\": \"baseUrl\", \"value\": \"$URL\"}, {\"name\": \"apiKey\", \"value\": \"$API_KEY\"}]}" > /dev/null
          fi
        }
        add_to_prowlarr "Sonarr" "http://localhost:${toString config.ports.sonarr}" "$SONARR_KEY" "SonarrSettings"
        add_to_prowlarr "Radarr" "http://localhost:${toString config.ports.radarr}" "$RADARR_KEY" "RadarrSettings"
      fi

      echo "Automation Complete."
    '';
  };
}
