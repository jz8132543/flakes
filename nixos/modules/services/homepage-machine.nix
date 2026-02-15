{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.networking) fqdn;
in
{
  users.users.homepage-dashboard = {
    isSystemUser = true;
    group = "homepage-dashboard";
  };
  users.groups.homepage-dashboard = { };

  # Use a manual systemd service because the homepage-dashboard module only supports one instance
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
      CacheDirectory = "homepage-dashboard";
      ExecStart = "${pkgs.homepage-dashboard}/bin/homepage";
      Restart = "always";
      RestartSec = "5s";
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
      HOMEPAGE_VAR_SABNZBD_KEY=${config.sops.placeholder."media/sabnzbd_api_key"}
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
            href = "/jellyfin/";
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
            href = "/jellyseerr/";
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
            href = "/sonarr/";
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
            href = "/radarr/";
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
            href = "/prowlarr/";
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
            href = "/lidarr/";
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
            href = "/bazarr/";
            icon = "bazarr.png";
            description = "Subtitles";
          };
        }
        {
          "qBittorrent" = {
            href = "/qbit/";
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
            href = "/vertex/";
            icon = "vertex.png";
            description = "PT Manager";
          };
        }
        {
          "Autobrr" = {
            href = "/autobrr/";
            icon = "autobrr.png";
            description = "Auto Downloader";
          };
        }
        {
          "Sabnzbd" = {
            href = "/sabnzbd/";
            icon = "sabnzbd.png";
            description = "Usenet Downloader";
            widget = {
              type = "sabnzbd";
              url = "http://localhost:${toString config.ports.sabnzbd}";
              key = "{{HOMEPAGE_VAR_SABNZBD_KEY}}";
            };
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
