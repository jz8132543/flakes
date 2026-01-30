# Bazarr Auto-Configuration
# Automatically configures Bazarr with credentials and connects to Sonarr/Radarr
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.bazarr;
  bazarrDataDir = cfg.dataDir;
  bazarrPort = config.ports.bazarr;
in
{
  config = lib.mkIf cfg.enable {
    # Bazarr initialization service
    systemd.services.bazarr-auto-config = {
      description = "Auto-configure Bazarr";
      wantedBy = [ "multi-user.target" ];
      after = [
        "bazarr.service"
        "sonarr.service"
        "radarr.service"
      ];
      requires = [ "bazarr.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "bazarr";
        Group = "media";
      };

      path = with pkgs; [
        curl
        jq
        coreutils
        sqlite
        xmlstarlet
        python3
      ];

      script = ''
                set -euo pipefail
                
                BAZARR_URL="http://localhost:${toString bazarrPort}"
                DATA_DIR="${bazarrDataDir}"
                CONFIG_FILE="$DATA_DIR/config/config.yaml"
                DB_FILE="$DATA_DIR/db/bazarr.db"
                MARKER_FILE="$DATA_DIR/.auto-configured"
                PASSWORD_FILE="${config.sops.secrets."password".path}"
                SONARR_API_KEY_FILE="${config.sops.secrets."media/sonarr_api_key".path}"
                RADARR_API_KEY_FILE="${config.sops.secrets."media/radarr_api_key".path}"
                
                # Check if already configured
                if [ -f "$MARKER_FILE" ]; then
                  echo "Bazarr already configured, skipping..."
                  exit 0
                fi
                
                # Wait for Bazarr to start
                echo "Waiting for Bazarr to initialize..."
                for i in {1..60}; do
                  if curl -sf "$BAZARR_URL" >/dev/null 2>&1; then
                    break
                  fi
                  sleep 2
                done
                
                # Wait for config file to be created
                for i in {1..30}; do
                  if [ -f "$CONFIG_FILE" ]; then
                    break
                  fi
                  sleep 2
                done
                
                if [ ! -f "$CONFIG_FILE" ]; then
                  echo "Bazarr config file not found, waiting for service to initialize..."
                  exit 0
                fi
                
                echo "Configuring Bazarr..."
                
                # Read credentials
                if [ -f "$PASSWORD_FILE" ]; then
                  PASSWORD=$(cat "$PASSWORD_FILE")
                else
                  PASSWORD="changeme"
                fi
                
                SONARR_API_KEY=""
                RADARR_API_KEY=""
                
                if [ -f "$SONARR_API_KEY_FILE" ]; then
                  SONARR_API_KEY=$(cat "$SONARR_API_KEY_FILE")
                fi
                
                if [ -f "$RADARR_API_KEY_FILE" ]; then
                  RADARR_API_KEY=$(cat "$RADARR_API_KEY_FILE")
                fi
                
                # Stop Bazarr to modify config
                systemctl stop bazarr.service || true
                sleep 2
                
                # Update config using Python (bazarr uses YAML)
                python3 << PYEOF
        import yaml
        import os

        config_file = "$CONFIG_FILE"

        with open(config_file, 'r') as f:
            config = yaml.safe_load(f) or {}

        # Authentication settings
        if 'auth' not in config:
            config['auth'] = {}
        config['auth']['type'] = 'form'
        config['auth']['username'] = 'i'
        config['auth']['password'] = '''$PASSWORD'''

        # Sonarr settings
        if 'sonarr' not in config:
            config['sonarr'] = {}
        config['sonarr']['ip'] = '127.0.0.1'
        config['sonarr']['port'] = ${toString config.ports.sonarr}
        config['sonarr']['base_url'] = '/'
        if '''$SONARR_API_KEY''':
            config['sonarr']['apikey'] = '''$SONARR_API_KEY'''
        config['sonarr']['ssl'] = False

        # Radarr settings
        if 'radarr' not in config:
            config['radarr'] = {}
        config['radarr']['ip'] = '127.0.0.1'
        config['radarr']['port'] = ${toString config.ports.radarr}
        config['radarr']['base_url'] = '/'
        if '''$RADARR_API_KEY''':
            config['radarr']['apikey'] = '''$RADARR_API_KEY'''
        config['radarr']['ssl'] = False

        # General settings
        if 'general' not in config:
            config['general'] = {}
        config['general']['use_sonarr'] = True
        config['general']['use_radarr'] = True
        config['general']['serie_default_enabled'] = True
        config['general']['movie_default_enabled'] = True
        config['general']['serie_default_language'] = ['zh', 'en']
        config['general']['movie_default_language'] = ['zh', 'en']

        with open(config_file, 'w') as f:
            yaml.dump(config, f, default_flow_style=False)

        print("Bazarr config updated")
        PYEOF
                
                # Restart Bazarr
                systemctl start bazarr.service
                
                # Mark as configured
                touch "$MARKER_FILE"
                
                echo "Bazarr auto-configuration complete!"
                echo "Username: i"
      '';
    };
  };
}
