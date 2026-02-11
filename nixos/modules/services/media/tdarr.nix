{ config, pkgs, ... }:
let
  domain = "tv.dora.im";
in
{
  config = {
    services.nginx.virtualHosts.localhost.locations = {
      "/tdarr/" = {
        proxyPass = "http://127.0.0.1:${toString config.ports.tdarr-webui}/";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header X-Forwarded-Prefix /tdarr;
          auth_basic "Tdarr Access";
          auth_basic_user_file /data/.state/tdarr/nginx.htpasswd;
        '';
      };
      "/tdarr" = {
        return = "301 /tdarr/";
      };
    };

    services.traefik.dynamicConfigOptions.http.routers.nixflix-tdarr = {
      rule = "(Host(`${domain}`) || Host(`${config.networking.fqdn}`)) && PathPrefix(`/tdarr`)";
      entryPoints = [ "https" ];
      service = "nixflix-nginx";
    };

    virtualisation.oci-containers.containers.tdarr = {
      image = "docker://haveagitgat/tdarr:latest";
      volumes = [
        "/data/.state/tdarr/server:/app/server"
        "/data/.state/tdarr/configs:/app/configs"
        "/data/.state/tdarr/logs:/app/logs"
        "/data/media:/data/media"
        "/data/downloads:/data/downloads"
        "/tmp/tdarr-transcode:/temp"
      ];
      environment = {
        TZ = "Asia/Shanghai";
        serverIP = "0.0.0.0";
        serverPort = toString config.ports.tdarr-server;
        webUIPort = toString config.ports.tdarr-webui;
        internalNode = "true";
        nodeID = "MainNode";
        nodeIP = "0.0.0.0";
        nodePort = "8267";
      };
      extraOptions = [ "--network=host" ];
    };

    # Automate Tdarr Configuration
    systemd.services.tdarr-setup = {
      description = "Automate Tdarr Auth, Library and Plugin Setup";
      after = [ "podman-tdarr.service" ];
      wants = [ "podman-tdarr.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "30s";
      };
      path = [
        pkgs.curl
        pkgs.jq
        pkgs.apacheHttpd
      ];
      script = ''
        # 1. Generate Nginx htpasswd
        PASS=$(cat ${config.sops.secrets.password.path})
        htpasswd -b -c /data/.state/tdarr/nginx.htpasswd i "$PASS"
        chmod 644 /data/.state/tdarr/nginx.htpasswd

        URL="http://127.0.0.1:${toString config.ports.tdarr-server}"

        # 2. Wait for Tdarr API
        echo "Waiting for Tdarr API at $URL..."
        for i in {1..30}; do
          if curl -s "$URL/api/v2/get-nodes" > /dev/null; then
            break
          fi
          sleep 5
        done

        # 3. Configure Library and Plugin Stack via cruddb
        echo "Checking for existing libraries..."
        EXISTING_LIBS=$(curl -s -X POST "$URL/api/v2/cruddb" \
          -d '{"data":{"collection":"LibrarySettingsJSONDB","mode":"getAll"}}' \
          -H "Content-Type: application/json")

        if echo "$EXISTING_LIBS" | jq -e '.[] | select(.name == "Media")' > /dev/null; then
          echo "Tdarr 'Media' library already exists."
        else
          echo "Creating 'Media' library with AV1 stack..."
          
          # Define the library object with _id matching docID
          LIB_OBJ='{
            "_id": "Media",
            "name": "Media",
            "priority": 1,
            "sourcePath": "/data/media",
            "cachePath": "/temp",
            "pluginStack": [
              {
                "pluginId": "Tdarr_Plugin_MC93_Migz1FFMPEG_AV1",
                "name": "Migz-Transcode-Using-SVT-AV1",
                "type": "transcode",
                "inputs": {
                  "av1_preset": "6",
                  "crf": "24"
                }
              }
            ],
            "scanType": "both",
            "folderWatcher": true,
            "scheduledScan": false,
            "container": "mkv",
            "scanner": {
              "scanner": "Tdarr_Scanner_Video_File",
              "inputs": {}
            }
          }'
          
          # Wrap in cruddb insert payload
          PAYLOAD=$(jq -n \
            --argjson obj "$LIB_OBJ" \
            '{data: {collection: "LibrarySettingsJSONDB", mode: "insert", docID: "Media", obj: $obj}}')

          curl -s -X POST "$URL/api/v2/cruddb" \
            -d "$PAYLOAD" \
            -H "Content-Type: application/json"
          
          echo "Tdarr 'Media' library creation request sent via cruddb."
        fi
      '';
    };
  };
}
