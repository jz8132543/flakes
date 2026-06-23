{
  config,
  pkgs,
  ...
}:
let
  domain = "ha.${config.networking.domain}";
  dbName = "homeassistant";
  dbUser = "homeassistant";
  dbHost = "postgres.mag";
  dbUrl = "postgresql://${dbUser}@${dbHost}/${dbName}?sslmode=disable";
in
{
  services.home-assistant = {
    enable = true;
    extraPackages =
      python3Packages: with python3Packages; [
        gtts
        ibeacon-ble
        psycopg2
      ];
    extraComponents = [
      "bluetooth"
      "command_line"
      "default_config"
      "ffmpeg"
      "homekit"
      "jellyfin"
      "keyboard_remote"
      "logger"
      "met"
      "mobile_app"
      "open_meteo"
      "ping"
      "radio_browser"
      "shell_command"
      "vlc"
      "wake_on_lan"
      "whisper"
      "workday"
      "wyoming"
      "xiaomi_aqara"
      "xiaomi_ble"
      "xiaomi_miio"
      "zeroconf"
    ];
    customComponents = with pkgs; [
      haier
      home-assistant-custom-components.midea_ac
      home-assistant-custom-components.midea_ac_lan
      home-assistant-custom-components.midea-air-appliances-lan
      home-assistant-custom-components.xiaomi_miot
      home-assistant-custom-components.xiaomi_home
      home-assistant-custom-components.xiaomi_gateway3
    ];
    config = {
      default_config = { };

      homeassistant = {
        name = "nue0 smart home";
        unit_system = "metric";
        time_zone = config.time.timeZone;
      };

      http = {
        server_host = "127.0.0.1";
        server_port = 8123;
        use_x_forwarded_for = true;
        trusted_proxies = [
          "127.0.0.1"
        ];
      };

      recorder = {
        db_url = dbUrl;
      };
      homekit = { };
    };
  };

  systemd.services.home-assistant-db-init = {
    description = "Create Home Assistant PostgreSQL database and user";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = with pkgs; [
      postgresql_17
      coreutils
      gnugrep
    ];
    script = ''
      set -euo pipefail

      until pg_isready -h ${dbHost} -U postgres >/dev/null 2>&1; do
        sleep 2
      done

      if ! psql -h ${dbHost} -U postgres -d postgres -Atqc "SELECT 1 FROM pg_roles WHERE rolname = '${dbUser}'" | grep -qx 1; then
        psql -h ${dbHost} -U postgres -d postgres -v ON_ERROR_STOP=1 -c "CREATE ROLE ${dbUser} LOGIN"
      fi

      if ! psql -h ${dbHost} -U postgres -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname = '${dbName}'" | grep -qx 1; then
        psql -h ${dbHost} -U postgres -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE ${dbName} OWNER ${dbUser}"
      fi
    '';
  };

  systemd.services.home-assistant.after = [ "home-assistant-db-init.service" ];
  systemd.services.home-assistant.requires = [ "home-assistant-db-init.service" ];

  services.traefik.proxies.home-assistant = {
    rule = "Host(`${domain}`)";
    target = "http://127.0.0.1:8123";
  };

  services.restic.backups.borgbase.paths = [
    config.services.home-assistant.configDir
  ];

  environment.global-persistence.directories = [
    config.services.home-assistant.configDir
  ];
}
