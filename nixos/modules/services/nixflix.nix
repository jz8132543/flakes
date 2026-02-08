# Nixflix Media Stack
# Declarative media server configuration using nixflix
# https://github.com/kiriwalawren/nixflix
#
# Usage in nixos/hosts/{host}/default.nix:
#   (import nixosModules.services.nixflix { })                    # All enabled (default)
#   (import nixosModules.services.nixflix { jellyfin = false; })  # Disable Jellyfin
#
# Parameters (all default to true):
#   jellyfin, jellyseerr, sonarr, radarr, prowlarr, lidarr,
#   sabnzbd, bazarr, qbittorrent, recyclarr, flaresolverr
{
  lib,
  pkgs,
  config,
  inputs,
  nixosModules,
  ...
}:
let
  domain = "tv.dora.im";

  navHtmlDir = ./../../../conf/nixflix;

  subpathProxyConfig = import ./../../../conf/nixflix/subpath-proxy.nix;

  finalNavHtml = pkgs.runCommand "nixflix-nav-html" { } ''
    mkdir -p $out
    substitute ${navHtmlDir}/nav.html $out/nav.html \
      --replace "@AUTOBRR_URL@" "http://tv.mag:${toString config.ports.autobrr}/" \
      --replace "@VERTEX_URL@" "http://tv.mag:${toString config.ports.vertex}/" \
      --replace "@IYUU_URL@" "http://tv.mag:${toString config.ports.iyuu}/"
  '';
in
{
  imports = [
    inputs.nixflix.nixosModules.nixflix
    nixosModules.services.qbittorrent
    nixosModules.services.traefik
  ];

  config = {
    # Core nixflix configuration (official documentation pattern)
    nixflix = {
      enable = true;
      mediaDir = "/data/media";
      stateDir = "/data/.state";
      mediaUsers = [
        "tippy"
        "root"
      ];

      theme = {
        enable = true;
        name = "nord";
      };

      nginx.enable = true;
      postgres.enable = false; # Use existing postgres module

      sonarr = {
        enable = true;
        group = "media";
        config = {
          apiKey = {
            _secret = config.sops.secrets."media/sonarr_api_key".path;
          };
          hostConfig = {
            username = "i";
            password = {
              _secret = config.sops.secrets."password".path;
            };
            urlBase = "/sonarr";
          };

        };
      };

      radarr = {
        enable = true;
        group = "media";
        config = {
          apiKey = {
            _secret = config.sops.secrets."media/radarr_api_key".path;
          };
          hostConfig = {
            username = "i";
            password = {
              _secret = config.sops.secrets."password".path;
            };
            urlBase = "/radarr";
          };

        };
      };

      prowlarr = {
        enable = true;
        group = "media";
        config = {
          apiKey = {
            _secret = config.sops.secrets."media/prowlarr_api_key".path;
          };
          hostConfig = {
            username = "i";
            password = {
              _secret = config.sops.secrets."password".path;
            };
            urlBase = "/prowlarr";
          };
          # Native Prowlarr applications configuration
          applications = [
            {
              name = "Sonarr";
              implementationName = "Sonarr";
              apiKey = {
                _secret = config.sops.secrets."media/sonarr_api_key".path;
              };
            }
            {
              name = "Radarr";
              implementationName = "Radarr";
              apiKey = {
                _secret = config.sops.secrets."media/radarr_api_key".path;
              };
            }
            {
              name = "Lidarr";
              implementationName = "Lidarr";
              apiKey = {
                _secret = config.sops.secrets."media/lidarr_api_key".path;
              };
            }
          ];
          # PT Indexers
          indexers = [
            {
              id = 0;
              name = "M-Team - TP";
              enable = true;
              freeleechOnly = true;
              baseUrl = "https://kp.m-team.cc/";
              apiKey = {
                _secret = config.sops.secrets."media/mteam_api_key".path;
              };
            }
            {
              # id = 1;
              name = "PTTime";
              enable = true;
              baseUrl = "https://www.pttime.org/";
              # freeleechOnly = true;
              # searchFreeleechOnly = true;
              username = {
                _secret = config.sops.secrets."media/pttime_username".path;
              };
              password = {
                _secret = config.sops.secrets."password".path;
              };
            }
          ];
          downloadClients = [
            {
              name = "qBittorrent";
              implementationName = "qBittorrent";
              apiKey = "";
              host = "127.0.0.1";
              port = config.ports.qbittorrent;
              username = "i";
              password = {
                _secret = config.sops.secrets."password".path;
              };
            }
          ];
        };
      };

      lidarr = {
        enable = true;
        group = "media";
        config = {
          apiKey = {
            _secret = config.sops.secrets."media/lidarr_api_key".path;
          };
          hostConfig = {
            username = "i";
            password = {
              _secret = config.sops.secrets."password".path;
            };
            urlBase = "/lidarr";
          };

        };
      };

      sabnzbd = {
        enable = true;
        group = "media";
        settings = {
          misc = {
            port = config.ports.sabnzbd;
            api_key = {
              _secret = config.sops.secrets."media/sabnzbd_api_key".path;
            };
            nzb_key = {
              _secret = config.sops.secrets."media/sabnzbd_nzb_key".path;
            };
            host_whitelist = [
              domain
              "localhost"
              "127.0.0.1"
              config.networking.fqdn
            ];
          };
        };
      };

      recyclarr = {
        enable = true;
        group = "media";
        cleanupUnmanagedProfiles = true;
      };

      jellyfin = {
        enable = true;
        users = {
          i = {
            mutable = false;
            policy.isAdministrator = true;
            password = {
              _secret = config.sops.secrets."password".path;
            };
          };
        };
      };

      jellyseerr = {
        enable = true;
        apiKey = {
          _secret = config.sops.secrets."media/jellyseerr_api_key".path;
        };
      };

      sonarr-anime = {
        enable = true;
        group = "media";
        config = {
          hostConfig = {
            username = "i";
            password = {
              _secret = config.sops.secrets."password".path;
            };
            urlBase = "/sonarr-anime";
          };
          apiKey = {
            _secret = config.sops.secrets."media/sonarr_api_key".path;
          };
        };
      };
    };

    # Consolidated Services Configuration
    services = {
      # Bazarr - Subtitle Management (native service)
      bazarr = {
        enable = true;
        group = "media";
        listenPort = config.ports.bazarr;
      };

      # FlareSolverr - Cloudflare bypass
      flaresolverr = {
        enable = true;
        port = config.ports.flaresolverr;
      };

      autobrr = {
        enable = true;
        secretFile = config.sops.secrets."media/autobrr_session_token".path;
        settings = {
          host = "0.0.0.0";
          port = config.ports.autobrr;
          baseUrl = "/autobrr/";
          database = {
            type = "sqlite";
            dsn = "/data/.state/autobrr/autobrr.db";
          };
          # metricsBasicAuthUsers = "i:$2y$05$yaH6RqWhDQGPvLI7vyVdY.EsH8LBrNaAS30HJwXiCHziIFf7csVbi";
        };
      };

      nginx = {
        enable = lib.mkForce true;
        commonHttpConfig = ''
          map $http_upgrade $connection_upgrade {
            default upgrade;
            ""      close;
          }
        '';
        virtualHosts.localhost = {
          listen = lib.mkForce [
            {
              addr = "127.0.0.1";
              port = config.ports.nginx;
            }
          ];
          # Make nginx use correct external domain for redirects
          serverName = lib.mkForce domain;
          serverAliases = [ config.networking.fqdn ];
          extraConfig = ''
            absolute_redirect off;

            # Pass correct headers for auth
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header Cookie $http_cookie;
            proxy_set_header Connection $http_connection;
          '';
          locations = {
            "/" = {
              extraConfig = ''
                root ${finalNavHtml};
                try_files /nav.html =404;
                default_type text/html;
              '';
            };
            "/bazarr" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.bazarr}";
              proxyWebsockets = true;
              extraConfig = subpathProxyConfig {
                path = "bazarr";
                port = config.ports.bazarr;
              };
            };
            "/autobrr/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.autobrr}";
              proxyWebsockets = true;
            };
            "/autobrr" = {
              return = "301 /autobrr/";
            };
            "/qbit/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.qbittorrent}/";
              proxyWebsockets = true;
              extraConfig = subpathProxyConfig {
                path = "qbit";
                port = config.ports.qbittorrent;
              };
            };
            "/qbit" = {
              return = "301 /qbit/";
            };

            "/vertex/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.vertex}/";
              proxyWebsockets = true;
              extraConfig = subpathProxyConfig {
                path = "vertex";
                port = config.ports.vertex;
              };
            };
            "/vertex" = {
              return = "301 /vertex/";
            };
            # Proxy Service Worker to Vertex backend to fix root 404
            "/service-worker.js" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.vertex}/service-worker.js";
              extraConfig = ''
                # Allow cross-scope SW registration if needed, though proxying usually avoids this
                proxy_set_header X-Forwarded-Host $host;
              '';
            };

            "/iyuu/" = {
              proxyPass = "http://127.0.0.1:8777/";
              proxyWebsockets = true;
              extraConfig = subpathProxyConfig {
                path = "iyuu";
                port = 8777;
              };
            };
            "/iyuu" = {
              return = "301 /iyuu/";
            };

            "/whoami/" = {
              proxyPass = "http://127.0.0.1:8082/";
              proxyWebsockets = true;
              extraConfig = subpathProxyConfig {
                path = "whoami";
                port = 8082;
              };
            };
            "/whoami" = {
              return = "301 /whoami/";
            };

            #            "/moviepilot/" = {
            #              proxyPass = "http://127.0.0.1:${toString (config.ports.moviepilot or 3000)}/";
            #              proxyWebsockets = true;
            #            };
            #            "/moviepilot" = {
            #              return = "301 /moviepilot/";
            #            };

            # Delegated to nixflix nginx: sonarr, radarr, lidarr, sabnzbd, jellyfin, jellyseerr, prowlarr
          };
        };
      };

      traefik.dynamicConfigOptions.http = {
        routers = {
          nixflix-nav = {
            rule = "Host(`${domain}`) && Path(`/`)";
            entryPoints = [ "https" ];
            service = "nixflix-nginx";
          };
          nixflix-apps = {
            rule = "(Host(`${domain}`) || Host(`${config.networking.fqdn}`)) && (PathPrefix(`/bazarr`) || PathPrefix(`/sonarr`) || PathPrefix(`/sonarr-anime`) || PathPrefix(`/radarr`) || PathPrefix(`/prowlarr`) || PathPrefix(`/lidarr`) || PathPrefix(`/sabnzbd`) || PathPrefix(`/jellyfin`) || PathPrefix(`/jellyseerr`) || PathPrefix(`/autobrr`) || PathPrefix(`/iyuu`) || PathPrefix(`/qbit`) || PathPrefix(`/vertex`) || PathPrefix(`/whoami`))";
            entryPoints = [ "https" ];
            service = "nixflix-nginx";
          };
        };
        services = {
          nixflix-nginx.loadBalancer.servers = [
            { url = "http://127.0.0.1:${toString config.ports.nginx}"; }
          ];
        };
      };
    };

    # Consolidated Systemd Configuration
    systemd = {
      tmpfiles.rules = [
        "Z /data 0777 root media -"
        "Z /data/media 0777 root media -"
        "Z /data/downloads 0777 root media -"
        "Z /data/downloads/usenet 0777 sabnzbd media -"
        "Z /data/downloads/usenet/incomplete 0777 sabnzbd media -"
        "Z /data/downloads/usenet/complete 0777 sabnzbd media -"
        "Z /data/.state 0777 root media -"

        "Z /data/.state/jellyfin 0777 jellyfin media -"
        "Z /data/.state/jellyseerr 0777 jellyseerr media -"
        "Z /data/.state/sonarr 0777 sonarr media -"
        "Z /data/.state/sonarr-anime 0777 sonarr-anime media -"
        "Z /data/.state/radarr 0777 radarr media -"
        "Z /data/.state/prowlarr 0777 prowlarr media -"
        "Z /data/.state/lidarr 0777 lidarr media -"
        "Z /data/.state/sabnzbd 0777 sabnzbd media -"
        "Z /data/.state/recyclarr 0777 recyclarr media -"
        "Z /data/.state/autobrr 0777 autobrr media -"
        "Z /data/.state/vertex 0777 root media -"
        "Z /data/.state/iyuu 0777 root media -"
        "Z /var/lib/bazarr 0777 bazarr media -"

        "Z /var/lib/iyuu 0777 iyuu media -"
        "Z /var/lib/autobrr 0777 autobrr media -"
      ];

      targets.postgresql-ready = {
        description = "PostgreSQL is ready for connections";
        after = [ "postgresql.service" ];
        requires = [ "postgresql.service" ];
        wantedBy = [ "multi-user.target" ];
      };

      services =
        (lib.listToAttrs (
          map
            (name: {
              inherit name;
              value.serviceConfig.Restart = lib.mkForce "on-failure";
            })
            [
              "jellyfin"
              "jellyseerr"
              "sonarr"
              "radarr"
              "prowlarr"
              "lidarr"
              "sabnzbd"
              "bazarr"
              "flaresolverr"
            ]
        ))
        // (lib.listToAttrs (
          map
            (name: {
              inherit name;
              value.serviceConfig.TimeoutStartSec = "1min";
            })
            [
              "sonarr-config"
              "radarr-config"
              "prowlarr-config"
              "lidarr-config"
              "sonarr-rootfolders"
              "radarr-rootfolders"
              "lidarr-rootfolders"
              "sonarr-downloadclients"
              "radarr-downloadclients"
              "prowlarr-downloadclients"
              "lidarr-downloadclients"
              "sonarr-delayprofiles"
              "radarr-delayprofiles"
              "lidarr-delayprofiles"
              "prowlarr-applications"
              "sabnzbd-categories"
              "jellyfin-setup-wizard"
              "jellyfin-system-config"
              "jellyfin-encoding-config"
              "jellyfin-branding-config"
              "jellyfin-libraries"
              "jellyseerr-setup"
              "jellyseerr-sonarr"
              "jellyseerr-radarr"
              "jellyseerr-libraries"
            ]
        ))
        // {
          sabnzbd-categories.enable = lib.mkForce false;

          media-stack-init = {
            description = "Automated configuration for media stack connections";
            after = [
              "sonarr.service"
              "radarr.service"
              "prowlarr.service"
              "bazarr.service"
              "qbittorrent.service"
              "postgresql-ready.target"
              "autobrr-user-init.service"
            ];
            wants = [
              "sonarr.service"
              "radarr.service"
              "prowlarr.service"
              "bazarr.service"
              "qbittorrent.service"
              "autobrr-user-init.service"
            ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              Restart = "on-failure";
              RestartSec = "30s";
              TimeoutStartSec = "1min";
            };
            path = [
              pkgs.curl
              pkgs.coreutils
            ];
            script = ''
              # Wait for all services to be healthy
              for service in sonarr:${toString config.ports.sonarr}/sonarr \
                             radarr:${toString config.ports.radarr}/radarr \
                             lidarr:${toString config.ports.lidarr}/lidarr \
                             prowlarr:${toString config.ports.prowlarr}/prowlarr \
                             bazarr:${toString config.ports.bazarr}/ \
                             autobrr:${toString config.ports.autobrr}/autobrr \
                             vertex:${toString config.ports.vertex}/vertex \
                             qbittorrent:${toString config.ports.qbittorrent}/ \
                             sonarr-anime:8990/sonarr-anime; do
                host="''${service%%:*}"
                path_port="''${service#*:}"
                until curl -s "http://127.0.0.1:$path_port" > /dev/null; do
                  echo "Waiting for $host on $path_port..."
                  sleep 5
                done
              done

              # Run unified setup script
              # Run unified setup script
              ${pkgs.python3.withPackages (ps: [ ps.requests ])}/bin/python3 ${navHtmlDir}/setup.py \
                --bazarr-url "http://127.0.0.1:${toString config.ports.bazarr}/api" \
                --prowlarr-url "http://127.0.0.1:${toString config.ports.prowlarr}/prowlarr" \
                --sonarr-url "http://127.0.0.1:${toString config.ports.sonarr}/sonarr" \
                --radarr-url "http://127.0.0.1:${toString config.ports.radarr}/radarr" \
                --sonarr-key-file "${config.sops.secrets."media/sonarr_api_key".path}" \
                --radarr-key-file "${config.sops.secrets."media/radarr_api_key".path}" \
                --prowlarr-key-file "${config.sops.secrets."media/prowlarr_api_key".path}" \
                --password-file "${config.sops.secrets."password".path}" \
                --qbit-port "${toString config.ports.qbittorrent}" \
                --sonarr-port "${toString config.ports.sonarr}" \
                --radarr-port "${toString config.ports.radarr}" \
                --sonarr-anime-url "http://127.0.0.1:8990/sonarr-anime" \
                --sonarr-anime-key-file "${config.sops.secrets."media/sonarr_api_key".path}" \
                --mteam-rss-file "${config.sops.secrets."media/mteam_rss_url".path}" \
                --pttime-rss-file "${config.sops.secrets."media/pttime_rss_url".path}" \
                --lidarr-url "http://127.0.0.1:${toString config.ports.lidarr}/lidarr" \
                --lidarr-key-file "${config.sops.secrets."media/lidarr_api_key".path}"
            '';
          };

          # Fix autobrr service - Ensure correct User/Group and permissions for /data
          autobrr.serviceConfig = {
            DynamicUser = lib.mkForce false;
            User = lib.mkForce "autobrr";
            Group = lib.mkForce "media";
            ReadWritePaths = [
              "/data/.state/autobrr"
              "/var/lib/autobrr"
            ];
          };

          # autobrr-user-init = {
          #   description = "Setup Autobrr User";
          #   after = [ "autobrr.service" ];
          #   wants = [ "autobrr.service" ];
          #   wantedBy = [ "multi-user.target" ];
          #   serviceConfig = {
          #     Type = "oneshot";
          #     User = "autobrr";
          #     Group = "media";
          #     WorkingDirectory = "/data/.state/autobrr";
          #   };
          #   script = ''
          #     # Allow autobrr to initialize
          #     sleep 10
          #
          #     PASSWORD=$(cat ${config.sops.secrets."password".path})
          #     CONFIG_FILE="/data/.state/autobrr/config.toml"
          #
          #     # Ensure user exists (idempotent via || echo)
          #     ${pkgs.autobrr}/bin/autobrrctl --config /data/.state/autobrr create-user i <<< "$PASSWORD" || echo "User creation failed or user exists"
          #
          #     # Update metricsBasicAuthUsers in config.toml
          #     if [ -f "$CONFIG_FILE" ]; then
          #       # Use sed to replace the line with the specific hash requested
          #       sed -i "s|metricsBasicAuthUsers = .*|metricsBasicAuthUsers = 'i:\$2y\$05\$yaH6RqWhDQGPvLI7vyVdY.EsH8LBrNaAS30HJwXiCHziIFf7csVbi'|" "$CONFIG_FILE"
          #       echo "Updated metricsBasicAuthUsers in $CONFIG_FILE"
          #     else
          #        echo "Config file not found at $CONFIG_FILE"
          #     fi
          #
          #     # Inject API Key for setup.py
          #     API_KEY=$(cat ${config.sops.secrets."media/autobrr_session_token".path})
          #     DB_FILE="/data/.state/autobrr/autobrr.db"
          #     if [ -f "$DB_FILE" ]; then
          #       ${pkgs.sqlite}/bin/sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO api_key (name, key) VALUES ('setup', '$API_KEY');"
          #       echo "Injected API Key into $DB_FILE"
          #     fi
          #   '';
          # };

          jellyfin.serviceConfig = {
            PrivateUsers = lib.mkForce false;
            UMask = "0002";
          };
          sonarr.serviceConfig.UMask = "0002";
          radarr.serviceConfig.UMask = "0002";
          prowlarr.serviceConfig.UMask = "0002";
          lidarr.serviceConfig.UMask = "0002";
          sabnzbd.serviceConfig.UMask = "0002";
          jellyseerr.serviceConfig.UMask = "0002";
          sonarr-anime.serviceConfig.UMask = "0002";
          bazarr.serviceConfig.UMask = "0002";
          qbittorrent.serviceConfig.UMask = "0002"; # Already has group but ensure umask
          autobrr.serviceConfig.UMask = "0002";
        };
    };

    # Other system settings (Boot, Networking, Users, SOPs, Containers)
    boot.kernel.sysctl = {
      "net.ipv4.tcp_max_orphans" = lib.mkDefault 65535;
      "net.ipv4.tcp_sack" = lib.mkDefault 1;
      "net.ipv4.tcp_timestamps" = lib.mkDefault 1;
      "net.core.optmem_max" = lib.mkDefault 65535;
      "fs.nr_open" = lib.mkDefault 2097152;
      "net.ipv4.tcp_mem" = lib.mkDefault "786432 1048576 134217728";
      "net.ipv4.udp_mem" = lib.mkDefault "786432 1048576 134217728";
    };

    networking.hosts."127.0.0.1" = [
      "sonarr"
      "radarr"
      "prowlarr"
      "lidarr"
      "sabnzbd"
      "bazarr"
      "qbittorrent"
    ];

    environment.global-persistence.directories = [
      "/data"
      "/var/lib/bazarr"
      "/data/.state/autobrr"
    ];

    users.users.bazarr = {
      isSystemUser = true;
      group = "media";
      uid = config.ids.uids.bazarr;
    };
    users.groups.bazarr.gid = config.ids.gids.bazarr;

    users.users.iyuu = {
      isSystemUser = true;
      group = "media";
      uid = config.ids.uids.iyuu;
      home = "/var/lib/iyuu";
      createHome = true;
    };
    users.groups.iyuu.gid = config.ids.gids.iyuu;

    users.users.autobrr = {
      isSystemUser = true;
      group = "media";
      uid = config.ids.uids.autobrr;
      home = "/var/lib/autobrr";
      createHome = true;
    };
    users.groups.autobrr.gid = config.ids.gids.autobrr;

    sops.templates."iyuu-env" = {
      content = ''
        SERVER_LISTEN_PORT=${toString config.ports.iyuu}
        SERVER_LISTEN_IP=0.0.0.0
        IYUU_TOKEN=${config.sops.placeholder."media/iyuu_token"}
        CONFIG_NOT_MYSQL=1
        # IYUU_APPID=
      '';
      owner = "iyuu";
      group = "media";
    };

    #    sops.templates."moviepilot-env" = {
    #      content = ''
    #        SUPERUSER_PASSWORD=${config.sops.placeholder.password}
    #        API_TOKEN=${config.sops.placeholder."media/moviepilot_api_key"}
    #        QB_PASSWORD=${config.sops.placeholder.password}
    #        JELLYFIN_API_KEY=${config.sops.placeholder."media/jellyfin_api_key"}
    #        JELLYFIN_PASSWORD=${config.sops.placeholder.password}
    #      '';
    #      owner = "root";
    #    };

    virtualisation.oci-containers = {
      backend = "podman";
      containers.vertex = {
        image = "docker://lswl/vertex:latest";
        volumes = [
          "/data/.state/vertex:/vertex"
          "/data/downloads/torrents:/data/downloads/torrents"
        ];
        environment = {
          TZ = "Asia/Shanghai";
          PORT = toString config.ports.vertex;
          BASE_PATH = "/vertex";
          USERNAME = "i";
          HOST = "0.0.0.0";
        };
        environmentFiles = [ config.sops.secrets.password.path ]; # This file contains PASSWORD=...
        extraOptions = [ "--network=host" ];
      };

      #      containers.moviepilot = {
      #        image = "jxxghp/moviepilot:latest";
      #        volumes = [
      #          "/data/.state/moviepilot:/config"
      #          "/data/.state/moviepilot/core:/moviepilot/.cache/ms-playwright"
      #          "/data/media:/media"
      #          "/data/downloads:/downloads"
      #          "/data/.state/moviepilot/plugins:/app/plugins"
      #          "/run/podman/podman.sock:/var/run/docker.sock:ro"
      #        ];
      #        environment = {
      #          TZ = "Asia/Shanghai";
      #          PUID = "0";
      #          PGID = "0";
      #          UMASK = "022";
      #          WORKDIR = "/moviepilot";
      #          CONFIG_DIR = "/config";
      #          NGINX_PORT = toString (config.ports.moviepilot or 3000);
      #          PORT = toString (config.ports.moviepilot or 3000);
      #          BIG_MEMORY_MODE = "false";
      #          DOWNLOADER = "qbittorrent";
      #          QB_HOST = "127.0.0.1:${toString config.ports.qbittorrent}";
      #          QB_USER = "i";
      #          MEDIASERVER = "jellyfin";
      #          JELLYFIN_HOST = "http://127.0.0.1:8096";
      #          PLUGIN_MARKET = "https://github.com/jxxghp/MoviePilot-Plugins,https://github.com/thsrite/MoviePilot-Plugins";
      #        };
      #        environmentFiles = [ config.sops.templates."moviepilot-env".path ];
      #        extraOptions = [
      #          "--network=host"
      #          "--hostname=moviepilot"
      #        ];
      #      };

      containers.iyuu = {
        image = "docker://iyuucn/iyuuplus:latest";
        volumes = [
          "/data/.state/iyuu:/iyuu"
          "/data/downloads/torrents:/data/downloads/torrents"
        ];
        environment = {
          TZ = "Asia/Shanghai";
          # For initial login if supported by image, or consistency
          IYUU_ADMIN_USER = "i";
        };
        environmentFiles = [
          config.sops.templates."iyuu-env".path
          config.sops.secrets.password.path # Adds PASSWORD=...
        ];
        extraOptions = [ "--network=host" ];
      };

      containers.whoami = {
        image = "docker.io/traefik/whoami";
        cmd = [
          "--port"
          "8082"
        ];
        extraOptions = [ "--network=host" ];
      };
    };

    sops.secrets =
      let
        mkSecret = mode: name: { inherit mode; } // { inherit name; };
        mkArr =
          mode: names:
          builtins.listToAttrs (
            map (n: {
              name = n;
              value = mkSecret mode n;
            }) names
          );
      in
      mkArr "0444" [ "password" ]
      // mkArr "0400" [
        "media/sonarr_api_key"
        "media/radarr_api_key"
        "media/prowlarr_api_key"
        "media/jellyfin_api_key"
        "media/jellyseerr_api_key"
        "media/lidarr_api_key"
        "media/sabnzbd_api_key"
        "media/sabnzbd_nzb_key"
        "media/mteam_api_key"
        "media/pttime_api_key"
        "media/iyuu_token"
        "media/autobrr_session_token"
        "media/pttime_username"
        "media/mteam_rss_url"
        "media/pttime_rss_url"
        "media/moviepilot_api_key"
        "media/jellyfin_api_key" # Explicitly included as it was missing from the list but used
      ];
    services.restic.backups.borgbase.paths = [
      "/data/.state/vertex/db/sql.db"
    ];
  };
}
