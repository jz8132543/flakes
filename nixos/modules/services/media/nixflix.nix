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
  navHtmlDir = ./../../../../conf/media;
  finalNavHtml = navHtmlDir;

  # Simple fallback login page for Vertex (bypasses Vue frontend issues)
  vertexLoginHtml = ./../../../../conf/media/vertex-login.html;
in
{
  imports = [
    inputs.nixflix.nixosModules.nixflix
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
              # freeleechOnly = false;
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
      homepage-dashboard.enable = false;

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

            # --- Custom Services (not managed by nixflix) ---
            "/bazarr/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.bazarr}";
              proxyWebsockets = true;
              extraConfig = ''
                # Bazarr handles url_base via its config.xml
                proxy_set_header X-Forwarded-Prefix /bazarr;
                # Preserve original request path for static assets
                proxy_set_header X-Script-Name /bazarr;
              '';
            };
            "/bazarr" = {
              return = "301 /bazarr/";
            };

            "/autobrr/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.autobrr}/";
              proxyWebsockets = true;
              extraConfig = ''
                proxy_set_header X-Forwarded-Prefix /autobrr;
              '';
            };
            "/autobrr" = {
              return = "301 /autobrr/";
            };

            "/qbit/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.qbittorrent}/";
              proxyWebsockets = true;
              extraConfig = ''
                # qBittorrent needs minimal config, it handles WebUI-RootFolder internally
                proxy_set_header X-Forwarded-Prefix /qbit;
              '';
            };
            "/qbit" = {
              return = "301 /qbit/";
            };

            "/vertex/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.vertex}/";
              proxyWebsockets = true;
              extraConfig = ''
                gunzip on;
                proxy_set_header Accept-Encoding "";

                sub_filter_types *;
                sub_filter_once off;

                # 1. Inject Base URL to fix Vue Router routing issues (White screen fix)
                sub_filter '<head>' '<head><base href="/vertex/">';

                # 2. Fix Service Worker and Manifest paths (Prevent 404 errors)
                sub_filter '"/service-worker.js"' '"/vertex/service-worker.js"';
                sub_filter "'/service-worker.js'" "'/vertex/service-worker.js'";
                sub_filter '"start_url":"/"' '"scope":"/vertex/","start_url":"/vertex/"';
                sub_filter '"scope":"/"' '"scope":"/vertex/"';

                # 3. Rewrite asset paths
                sub_filter 'src="/assets/' 'src="/vertex/assets/';
                sub_filter 'href="/assets/' 'href="/vertex/assets/';
                sub_filter 'content="/assets/' 'content="/vertex/assets/';
                sub_filter 'url("/assets/' 'url("/vertex/assets/';
                sub_filter '"src": "/assets/' '"src": "/vertex/assets/';
                sub_filter '"/assets/' '"/vertex/assets/';
                sub_filter "'/assets/" "'/vertex/assets/";

                # 4. Inject API Path Rewriter (Monkey Patching fetch/XHR)
                sub_filter '</head>' '<script>(function(){var f=window.fetch;window.fetch=function(u,o){if(typeof u==="string"&&u.startsWith("/api/"))u="/vertex"+u;return f(u,o);};var x=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(m,u){if(typeof u==="string"&&u.startsWith("/api/"))u="/vertex"+u;return x.apply(this,arguments);};})();</script></head>';

                proxy_redirect / /vertex/;
                proxy_set_header X-Forwarded-Prefix /vertex;
              '';
            };

            "/vertex" = {
              return = "301 /vertex/";
            };

            # Simple login page for Vertex (bypasses Vue frontend blank page issues)
            "= /vertex-login" = {
              alias = "${vertexLoginHtml}";
              extraConfig = ''
                default_type text/html;
              '';
            };

            "/iyuu/" = {
              proxyPass = "http://127.0.0.1:8777/";
              proxyWebsockets = true;
              extraConfig = ''
                proxy_set_header X-Forwarded-Prefix /iyuu;
              '';
            };
            "/iyuu" = {
              return = "301 /iyuu/";
            };

            "/whoami/" = {
              proxyPass = "http://127.0.0.1:8082/";
              proxyWebsockets = true;
              extraConfig = ''
                proxy_set_header X-Forwarded-Prefix /whoami;
              '';
            };
            "/whoami" = {
              return = "301 /whoami/";
            };

            "/dashboard/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.homepage}/";
              proxyWebsockets = true;
            };

            "/nav" = {
              return = "301 /";
            };

            # Services delegated to nixflix nginx: sonarr, radarr, lidarr, sabnzbd, jellyfin, jellyseerr, prowlarr, sonarr-anime
          };
        };
      };

      traefik.dynamicConfigOptions.http = {
        middlewares = {
          strip-tv = {
            stripPrefix = {
              prefixes = [ "/tv" ];
            };
          };
        };
        routers = {
          nixflix-nav = {
            # Allow access via domain or local fqdn, and via root path or /tv path
            rule = "(Host(`${domain}`) || Host(`${config.networking.fqdn}`)) && (Path(`/`) || PathPrefix(`/tv`))";
            entryPoints = [ "https" ];
            service = "nixflix-nginx";
            middlewares = [ "strip-tv" ];
          };
          nixflix-dashboard = {
            rule = "(Host(`${domain}`) || Host(`${config.networking.fqdn}`)) && PathPrefix(`/dashboard`)";
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
            ];
            wants = [
              "sonarr.service"
              "radarr.service"
              "prowlarr.service"
              "bazarr.service"
              "qbittorrent.service"
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
              pkgs.systemd
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
                             jellyfin:8096/health \
                             sonarr-anime:8990/sonarr-anime; do
                host="''${service%%:*}"
                path_port="''${service#*:}"
                until curl -s "http://127.0.0.1:$path_port" > /dev/null; do
                  echo "Waiting for $host on $path_port..."
                  sleep 5
                done
              done

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
                --lidarr-key-file "${config.sops.secrets."media/lidarr_api_key".path}" \
                --jellyfin-url "http://127.0.0.1:8096/jellyfin" \
                --jellyfin-env-file "/var/lib/homepage/jellyfin.env"

              # Restart homepage to pick up new env vars
              systemctl restart homepage-dashboard.service
            '';
          };

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
        };
    };

    # Containers
    users.users.iyuu = {
      isSystemUser = true;
      group = "media";
      uid = config.ids.uids.iyuu;
      home = "/var/lib/iyuu";
      createHome = true;
    };
    users.groups.iyuu.gid = config.ids.gids.iyuu;

    sops.templates."iyuu-env" = {
      content = ''
        SERVER_LISTEN_PORT=${toString config.ports.iyuu}
        SERVER_LISTEN_IP=0.0.0.0
        IYUU_TOKEN=${config.sops.placeholder."media/iyuu_token"}
        CONFIG_NOT_MYSQL=1
      '';
      owner = "iyuu";
      group = "media";
    };

    sops.templates."vertex-env" = {
      content = ''
        PASSWORD=${config.sops.placeholder.password}
      '';
      owner = "root";
      group = "root";
    };

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
        environmentFiles = [ config.sops.templates."vertex-env".path ];
        extraOptions = [ "--network=host" ];
      };

      containers.iyuu = {
        image = "docker://iyuucn/iyuuplus:latest";
        volumes = [
          "/data/.state/iyuu:/iyuu"
          "/data/downloads/torrents:/data/downloads/torrents"
        ];
        environment = {
          TZ = "Asia/Shanghai";
          IYUU_ADMIN_USER = "i";
        };
        environmentFiles = [
          config.sops.templates."iyuu-env".path
          config.sops.secrets.password.path
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

    services.restic.backups.borgbase.paths = [
      "/data/.state/vertex/db/sql.db"
    ];
  };
}
