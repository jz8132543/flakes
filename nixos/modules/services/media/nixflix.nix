{
  lib,
  config,
  inputs,
  nixosModules,
  ...
}:
let
  domain = "tv.dora.im";
  navHtmlDir = ./../../../../conf/media;
  finalNavHtml = navHtmlDir;
in
{
  imports = [
    inputs.nixflix.nixosModules.default
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

      # Synchronize nixflix internal IDs with system ID management
      globals = {
        inherit (config.ids) uids;
        inherit (config.ids) gids;
      };

      downloadsDir = "/data/downloads";

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
          rootFolders = [
            { path = "/data/media/tv"; }
          ];
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
          rootFolders = [
            { path = "/data/media/movies"; }
          ];
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
              baseUrl = "http://127.0.0.1:${toString config.ports.sonarr}/sonarr";
              prowlarrUrl = "http://127.0.0.1:${toString config.ports.prowlarr}/prowlarr";
            }
            {
              name = "Radarr";
              implementationName = "Radarr";
              apiKey = {
                _secret = config.sops.secrets."media/radarr_api_key".path;
              };
              baseUrl = "http://127.0.0.1:${toString config.ports.radarr}/radarr";
              prowlarrUrl = "http://127.0.0.1:${toString config.ports.prowlarr}/prowlarr";
            }
            {
              name = "Lidarr";
              implementationName = "Lidarr";
              apiKey = {
                _secret = config.sops.secrets."media/lidarr_api_key".path;
              };
              baseUrl = "http://127.0.0.1:${toString config.ports.lidarr}/lidarr";
              prowlarrUrl = "http://127.0.0.1:${toString config.ports.prowlarr}/prowlarr";
            }
            {
              name = "Sonarr Anime";
              implementationName = "Sonarr";
              apiKey = {
                _secret = config.sops.secrets."media/sonarr_api_key".path;
              };
              baseUrl = "http://127.0.0.1:${toString config.ports.sonarr-anime}/sonarr-anime";
              prowlarrUrl = "http://127.0.0.1:${toString config.ports.prowlarr}/prowlarr";
            }
          ];
          # PT Indexers
          indexers = [
            {
              name = "M-Team - TP";
              enable = true;
              implementationName = "Gazelle";
              fields = [
                {
                  name = "baseUrl";
                  value = "https://kp.m-team.cc/";
                }
                {
                  name = "apiKey";
                  value = {
                    _secret = config.sops.secrets."media/mteam_api_key".path;
                  };
                }
              ];
            }
            {
              name = "PTTime";
              enable = true;
              implementationName = "Unit3D";
              fields = [
                {
                  name = "baseUrl";
                  value = "https://www.pttime.org/";
                }
                {
                  name = "apiKey";
                  value = {
                    _secret = config.sops.secrets."media/pttime_rss_url".path; # Unit3D often uses RSS/API key interchangeably in some implementations, but here we likely need a real key.
                  };
                }
              ];
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
          rootFolders = [
            { path = "/data/media/music"; }
          ];
        };
      };

      recyclarr = {
        enable = true;
        group = "media";
        cleanupUnmanagedProfiles.enable = true;
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
          rootFolders = [
            { path = "/data/media/anime"; }
          ];
        };
      };
    };

    services = {
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
            "/tv/" = {
              extraConfig = ''
                root ${finalNavHtml};
                rewrite ^/tv/(.*)$ /$1 break;
                try_files /nav.html =404;
                default_type text/html;
              '';
            };
            "/tv" = {
              return = "301 /tv/";
            };

            # --- Custom Services (not managed by nixflix) ---
            "/bazarr/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.bazarr}/";
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

            "/whoami" = {
              return = "301 /whoami/";
            };

            "/jellyfin/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.jellyfin}";
              proxyWebsockets = true;
            };
            "/jellyfin" = {
              return = "301 /jellyfin/";
            };

            # Direct proxies to internal Arr services
            "/sonarr/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.sonarr}/sonarr/";
              proxyWebsockets = true;
            };
            "/sonarr" = {
              return = "301 /sonarr/";
            };

            "/radarr/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.radarr}/radarr/";
              proxyWebsockets = true;
            };
            "/radarr" = {
              return = "301 /radarr/";
            };

            "/lidarr/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.lidarr}/lidarr/";
              proxyWebsockets = true;
            };
            "/lidarr" = {
              return = "301 /lidarr/";
            };

            "/prowlarr/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.prowlarr}/prowlarr/";
              proxyWebsockets = true;
            };
            "/prowlarr" = {
              return = "301 /prowlarr/";
            };

            "/sonarr-anime/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.sonarr-anime}/sonarr-anime/";
              proxyWebsockets = true;
            };
            "/sonarr-anime" = {
              return = "301 /sonarr-anime/";
            };

            "/jellyseerr/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.jellyseerr}/";
              proxyWebsockets = true;
            };
            "/jellyseerr" = {
              return = "301 /jellyseerr/";
            };

          };
        };
      };

      traefik = {
        proxies = {
          nixflix-nav = {
            rule = "(Host(`${domain}`) || Host(`${config.networking.fqdn}`)) && PathPrefix(`/tv`)";
            target = "http://127.0.0.1:${toString config.ports.nginx}";
            middlewares = [ "strip-tv" ];
          };
          nixflix-apps = {
            rule = "(Host(`${domain}`) || Host(`${config.networking.fqdn}`)) && (PathPrefix(`/bazarr`) || PathPrefix(`/sonarr`) || PathPrefix(`/sonarr-anime`) || PathPrefix(`/radarr`) || PathPrefix(`/prowlarr`) || PathPrefix(`/lidarr`) || PathPrefix(`/sabnzbd`) || PathPrefix(`/jellyfin`) || PathPrefix(`/jellyseerr`) || PathPrefix(`/autobrr`) || PathPrefix(`/qbit`) || PathPrefix(`/whoami`) || PathPrefix(`/unmanic`))";
            target = "http://127.0.0.1:${toString config.ports.nginx}";
          };
        };

        dynamicConfigOptions.http.middlewares = {
          strip-tv.stripPrefix.prefixes = [ "/tv" ];
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
              value.serviceConfig.Restart = lib.mkDefault "on-failure";
            })
            [
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
              "jellyseerr-setup"
              "jellyseerr-sonarr"
              "jellyseerr-radarr"
              "jellyseerr-libraries"
            ]
        ))
        // {
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

    virtualisation.oci-containers = {
      backend = "podman";
      containers.whoami = {
        image = "docker.io/traefik/whoami";
        cmd = [
          "--port"
          "8082"
        ];
        extraOptions = [ "--network=host" ];
      };
    };

  };
}
