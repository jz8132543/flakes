{
  lib,
  config,
  inputs,
  ...
}:
{
  imports = [ inputs.nixflix.nixosModules.default ];

  config = {
    nixflix = {
      enable = true;
      mediaDir = "/data/media";
      stateDir = "/data/.state";
      mediaUsers = [
        "tippy"
        "root"
      ];

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
      postgres.enable = false;

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
          indexers = [
            {
              name = "M-Team - TP";
              enable = true;
              implementationName = "Gazelle";
              baseUrl = "https://kp.m-team.cc/";
              apiKey = {
                _secret = config.sops.secrets."media/mteam_api_key".path;
              };
            }
            /*
              {
                name = "PTTime";
                enable = true;
                implementationName = "Unit3D";
                baseUrl = "https://www.pttime.org/";
                username = {
                  _secret = config.sops.secrets."media/pttime_username".path;
                };
                apiKey = {
                  _secret = config.sops.secrets."media/pttime_api_key".path;
                };
              }
            */
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

      recyclarr = {
        enable = true;
        group = "media";
        cleanupUnmanagedProfiles.enable = true;
      };

      jellyseerr = {
        enable = true;
        jellyfin.adminUsername = "i";
        jellyfin.adminPassword = {
          _secret = config.sops.secrets."password".path;
        };
        settings.users.defaultPermissions = 1024;
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

    services.traefik.proxies = {
      autobrr = {
        rule = "Host(`${config.networking.fqdn}`) && PathPrefix(`/autobrr`)";
        target = "http://127.0.0.1:${toString config.ports.autobrr}";
        middlewares = [ "strip-prefix" ];
      };

      bazarr = {
        rule = "Host(`${config.networking.fqdn}`) && PathPrefix(`/bazarr`)";
        target = "http://127.0.0.1:${toString config.ports.bazarr}";
        middlewares = [ "strip-prefix" ];
      };

      whoami = {
        rule = "Host(`${config.networking.fqdn}`) && PathPrefix(`/whoami`)";
        target = "http://127.0.0.1:8082";
        middlewares = [ "strip-prefix" ];
      };
    };

    systemd = {
      services =
        (lib.listToAttrs (
          map
            (name: {
              inherit name;
              value.serviceConfig.Restart = lib.mkDefault "on-failure";
              value.serviceConfig.TimeoutStartSec = lib.mkDefault "5min";
            })
            [
              "jellyfin"
              "jellyseerr"
              "sonarr"
              "radarr"
              "prowlarr"
              "lidarr"
            ]
        ))
        // (lib.listToAttrs (
          map
            (name: {
              inherit name;
              value.serviceConfig.TimeoutStartSec = lib.mkForce "5min";
            })
            [
              "jellyfin-setup-wizard"
              "jellyfin-users-config"
              "jellyfin-system-config"
              "jellyfin-encoding-config"
              "jellyfin-branding-config"
              "jellyfin-libraries"
              "jellyseerr-setup"
              "jellyseerr-user-settings"
              "jellyseerr-jellyfin"
              "jellyseerr-libraries"
              "jellyseerr-sonarr"
              "jellyseerr-radarr"
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
            ]
        ))
        // {
          sonarr.serviceConfig.UMask = "0002";
          radarr.serviceConfig.UMask = "0002";
          prowlarr.serviceConfig.UMask = "0002";
          lidarr.serviceConfig.UMask = "0002";
          jellyseerr.serviceConfig.UMask = "0002";
          sonarr-anime.serviceConfig.UMask = "0002";
        };
    };

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
