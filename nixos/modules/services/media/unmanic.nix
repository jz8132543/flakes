{ config, pkgs, ... }:
let
  domain = "tv.dora.im";
in
{
  config = {
    services.nginx.virtualHosts.localhost.locations = {
      "/unmanic/" = {
        proxyPass = "http://127.0.0.1:${toString config.ports.unmanic}/";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header X-Forwarded-Prefix /unmanic;
          auth_basic "Unmanic Access";
          auth_basic_user_file /data/.state/unmanic/nginx.htpasswd;
        '';
      };
      "/unmanic" = {
        return = "301 /unmanic/";
      };
    };

    services.traefik.dynamicConfigOptions.http.routers.nixflix-unmanic = {
      rule = "(Host(`${domain}`) || Host(`${config.networking.fqdn}`)) && PathPrefix(`/unmanic`)";
      entryPoints = [ "https" ];
      service = "nixflix-nginx";
    };

    virtualisation.oci-containers.containers.unmanic = {
      image = "docker://josh5/unmanic:latest";
      volumes = [
        "/data/.state/unmanic:/config"
        "/data/media:/library"
        "/tmp/unmanic-transcode:/tmp"
      ];
      environment = {
        TZ = "Asia/Shanghai";
        PUID = "0";
        PGID = "0";
      };
      ports = [
        "${toString config.ports.unmanic}:8888"
      ];
      extraOptions = [ "--device=/dev/dri:/dev/dri" ];
    };

    # Automate Unmanic Auth Setup
    systemd.services.unmanic-setup = {
      description = "Automate Unmanic Auth Setup";
      requiredBy = [ "podman-unmanic.service" ];
      before = [ "podman-unmanic.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [
        pkgs.apacheHttpd
        pkgs.jq
      ];
      script = ''
        # Generate Nginx htpasswd
        PASS=$(cat ${config.sops.secrets.password.path})
        mkdir -p /data/.state/unmanic
        htpasswd -b -c /data/.state/unmanic/nginx.htpasswd i "$PASS"
        chmod 644 /data/.state/unmanic/nginx.htpasswd

        # Configure Unmanic Settings
        CONFIG_DIR="/data/.state/unmanic/.unmanic/config"
        SETTINGS_FILE="$CONFIG_DIR/settings.json"

        mkdir -p "$CONFIG_DIR"

        # Default settings if file doesn't exist
        if [ ! -f "$SETTINGS_FILE" ]; then
          echo '{
            "library_path": "/library",
            "number_of_workers": 3,
            "cache_path": "/tmp/unmanic",
            "schedule_full_scan_minutes": 60,
            "run_full_scan_on_start": false
          }' > "$SETTINGS_FILE"
        else
          # Update existing settings
          tmp=$(mktemp)
          ${pkgs.jq}/bin/jq '.number_of_workers = 3 | .library_path = "/library"' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
        fi
        chmod 644 "$SETTINGS_FILE"
      '';
    };
  };
}
