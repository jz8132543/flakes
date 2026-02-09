{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = {
    services.bazarr = {
      enable = true;
      group = "media";
      listenPort = config.ports.bazarr;
    };

    systemd.services.bazarr.serviceConfig = {
      Restart = lib.mkForce "on-failure";
      UMask = "0002";
    };

    # Configure Bazarr url_base for subpath support
    systemd.services.bazarr-config-urlbase = {
      description = "Configure Bazarr URL base for subpath routing";
      after = [ "bazarr.service" ];
      wants = [ "bazarr.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [
        pkgs.gnused
        pkgs.coreutils
      ];
      script = ''
        CONFIG_FILE="/var/lib/bazarr/config/config.xml"

        # Wait for Bazarr to create its config file
        for i in {1..30}; do
          if [ -f "$CONFIG_FILE" ]; then
            break
          fi
          echo "Waiting for Bazarr config file..."
          sleep 2
        done

        if [ ! -f "$CONFIG_FILE" ]; then
          echo "Bazarr config file not found after waiting"
          exit 0
        fi

        # Set url_base if not already set
        if ! grep -q "<base_url>" "$CONFIG_FILE"; then
          echo "Adding base_url to Bazarr config"
          sed -i 's|</general>|  <base_url>/bazarr</base_url>\n  </general>|' "$CONFIG_FILE"
          systemctl restart bazarr
        elif ! grep -q "<base_url>/bazarr</base_url>" "$CONFIG_FILE"; then
          echo "Updating base_url in Bazarr config"
          sed -i 's|<base_url>.*</base_url>|<base_url>/bazarr</base_url>|' "$CONFIG_FILE"
          systemctl restart bazarr
        else
          echo "Bazarr base_url already configured correctly"
        fi
      '';
    };

    users.users.bazarr = {
      isSystemUser = true;
      group = "media";
      uid = config.ids.uids.bazarr;
    };
    users.groups.bazarr.gid = config.ids.gids.bazarr;

    environment.global-persistence.directories = [
      "/var/lib/bazarr"
    ];
  };
}
