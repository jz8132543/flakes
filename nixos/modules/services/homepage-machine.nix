{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.networking) fqdn;
  inherit (config.networking) domain;
  media = rec {
    jellyfin = "https://jellyfin.${domain}/jellyfin";
    seerr = "https://seerr.${domain}";
    sonarr = "https://sonarr.${domain}";
    radarr = "https://radarr.${domain}";
    prowlarr = "https://prowlarr.${domain}";
    lidarr = "https://lidarr.${domain}";
    bazarr = "https://bazarr.${domain}";
    qbit = "https://qbit.${domain}";
    vertex = "https://vertex.${domain}";
    autobrr = "https://autobrr.${domain}";
  };
in
{
  users.users.homepage-machine = {
    isSystemUser = true;
    group = "homepage-machine";
  };
  users.groups.homepage-machine = { };

  # Use a manual systemd service because the homepage-machine module only supports one instance
  systemd.services.homepage-machine = {
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.StartLimitIntervalSec = 0;

    # Switch to DynamicUser and systemd-managed State/Cache directories so systemd
    # creates and owns the runtime directories without manual chown.
    serviceConfig = {
      Type = "simple";
      DynamicUser = "true";
      StateDirectory = "homepage-machine";
      CacheDirectory = "homepage-machine";
      Restart = "always";
      RestartSec = "5s";
      User = "homepage-machine";
      Group = "homepage-machine";
      ExecStart = "${pkgs.homepage-dashboard}/bin/homepage";
      WorkingDirectory = "/var/lib/homepage-machine";
      Environment = [
        "PORT=${toString config.ports.homepage-machine}"
        "HOMEPAGE_CONFIG_DIR=/var/lib/homepage-machine"
        "HOMEPAGE_BASEPATH=/home/"
        "HOMEPAGE_ALLOWED_HOSTS=*"
      ];
      EnvironmentFile = [
        "-/var/lib/homepage/jellyfin.env"
        config.sops.templates."homepage-machine.env".path
      ];
    };
  };

  sops.templates."homepage-machine.env" = {
    content = ''
      HOMEPAGE_VAR_SONARR_KEY=${config.sops.placeholder."media/sonarr_api_key"}
      HOMEPAGE_VAR_RADARR_KEY=${config.sops.placeholder."media/radarr_api_key"}
      HOMEPAGE_VAR_PROWLARR_KEY=${config.sops.placeholder."media/prowlarr_api_key"}
      HOMEPAGE_VAR_LIDARR_KEY=${config.sops.placeholder."media/lidarr_api_key"}
      HOMEPAGE_VAR_JELLYSEERR_KEY=${config.sops.placeholder."media/jellyseerr_api_key"}
      HOMEPAGE_VAR_PASSWORD=${config.sops.placeholder."password"}
      HOMEPAGE_VAR_GRAFANA_PASSWORD=${config.sops.placeholder."password"}
      HOMEPAGE_ALLOWED_HOSTS="*"
    '';
  };

  environment.etc."homepage-machine/settings.yaml".text = lib.generators.toYAML { } {
    title = "${config.networking.hostName} Dashboard";
    base = "https://${fqdn}/home/";
    language = "zh-Hans";
    background = {
      image = "https://images.unsplash.com/photo-1502790671504-542ad42d5189?auto=format&fit=crop&w=2560&q=80";
      blur = "sm";
      saturate = 50;
      brightness = 50;
    };
  };

  environment.etc."homepage-machine/services.yaml".text = lib.generators.toYAML { } [
    {
      "Media" = [
        {
          "Jellyfin" = {
            href = media.jellyfin;
            icon = "jellyfin.png";
            description = "Media Server";
            widget = {
              type = "jellyfin";
              url = "http://localhost:${toString config.ports.jellyfin}";
              key = "{{HOMEPAGE_VAR_JELLYFIN_GENERATED_KEY}}";
              enableBlocks = true;
              enableNowPlaying = true;
              enableUser = true;
              showEpisodeNumber = true;
              expandOneStreamToTwoRows = true;
            };
          };
        }
        {
          "Jellyseerr" = {
            href = media.seerr;
            icon = "jellyseerr.png";
            description = "Request Management";
            widget = {
              type = "jellyseerr";
              url = "http://localhost:${toString config.ports.jellyseerr}";
              key = "{{HOMEPAGE_VAR_JELLYSEERR_KEY}}";
            };
          };
        }
        {
          "Sonarr" = {
            href = media.sonarr;
            icon = "sonarr.png";
            description = "TV Series";
            widget = {
              type = "sonarr";
              url = "http://localhost:${toString config.ports.sonarr}";
              key = "{{HOMEPAGE_VAR_SONARR_KEY}}";
            };
          };
        }
        {
          "Radarr" = {
            href = media.radarr;
            icon = "radarr.png";
            description = "Movies";
            widget = {
              type = "radarr";
              url = "http://localhost:${toString config.ports.radarr}";
              key = "{{HOMEPAGE_VAR_RADARR_KEY}}";
              enableQueue = true;
            };
          };
        }
        {
          "Prowlarr" = {
            href = media.prowlarr;
            icon = "prowlarr.png";
            description = "Indexer Manager";
            widget = {
              type = "prowlarr";
              url = "http://localhost:${toString config.ports.prowlarr}";
              key = "{{HOMEPAGE_VAR_PROWLARR_KEY}}";
            };
          };
        }
        {
          "Lidarr" = {
            href = media.lidarr;
            icon = "lidarr.png";
            description = "Music";
            widget = {
              type = "lidarr";
              url = "http://localhost:${toString config.ports.lidarr}";
              key = "{{HOMEPAGE_VAR_LIDARR_KEY}}";
            };
          };
        }
        {
          "Bazarr" = {
            href = media.bazarr;
            icon = "bazarr.png";
            description = "Subtitles";
          };
        }
        {
          "qBittorrent" = {
            href = media.qbit;
            icon = "qbittorrent.png";
            description = "Torrent Client";
            widget = {
              type = "qbittorrent";
              url = "http://localhost:${toString config.ports.qbittorrent}";
              username = "i";
              password = "{{HOMEPAGE_VAR_PASSWORD}}";
              enableLeechProgress = false;
            };
          };
        }
        {
          "Vertex" = {
            href = media.vertex;
            icon = "vertex.png";
            description = "PT Manager";
          };
        }
        {
          "Autobrr" = {
            href = media.autobrr;
            icon = "autobrr.png";
            description = "Auto Downloader";
          };
        }
      ];
    }
    {
      "System" = [
        {
          "Traefik" = {
            href = "/dashboard/";
            icon = "traefik.png";
            description = "Reverse Proxy";
          };
        }
        {
          "PostgreSQL" = {
            icon = "postgresql.png";
            description = "Database";
          };
        }
        {
          "Syncthing" = {
            href = "/syncthing/";
            icon = "syncthing.png";
            description = "File Sync";
          };
        }
      ];
    }
  ];

  environment.etc."homepage-machine/widgets.yaml".text = lib.generators.toYAML { } [
    {
      resources = {
        cpu = true;
        disk = "/";
        memory = true;
        uptime = true;
        network = true;
        expanded = true;
      };
    }
    {
      datetime = {
        format = {
          timeStyle = "short";
        };
      };
    }
  ];

  services.traefik.proxies.homepage-machine = {
    rule = "Host(`${fqdn}`) && (Path(`/home`) || PathPrefix(`/home/`))";
    target = "http://127.0.0.1:${toString config.ports.homepage-machine}";
    priority = 50;
    middlewares = [ "strip-prefix" ];
  };

  services.traefik.proxies.homepage-machine-assets = {
    rule = "Host(`${fqdn}`) && (PathPrefix(`/home/_next`) || PathPrefix(`/_next`) || PathPrefix(`/home/images`) || PathPrefix(`/images`) || PathPrefix(`/home/api/config`) || PathPrefix(`/api/config`) || PathPrefix(`/home/icons`) || PathPrefix(`/icons`) || PathPrefix(`/home/site.webmanifest`) || PathPrefix(`/site.webmanifest`))";
    target = "http://127.0.0.1:${toString config.ports.homepage-machine}";
    priority = 50;
  };

}
