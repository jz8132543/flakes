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

    serviceConfig = {
      Type = "simple";
      StateDirectory = "homepage-machine";
      CacheDirectory = "homepage-dashboard";
      # ExecStartPre = pkgs.writeShellScript "prep-homepage" ''
      #   cp -f /etc/homepage-machine/*.yaml /var/lib/homepage-machine/
      # '';
      ExecStart = "${pkgs.homepage-dashboard}/bin/homepage";
      # ExecStartPost = pkgs.writeShellScript "check-homepage" ''
      #   # Wait up to 60 seconds for the service to be responsive
      #   for i in {1..60}; do
      #     # Accept 200 (OK) or 308 (Redirect) as proof of life
      #     CODE=$(${pkgs.curl}/bin/curl -k -s -o /dev/null -w "%{http_code}" http://localhost:${toString config.ports.homepage-machine}/)
      #     if [ "$CODE" = "200" ] || [ "$CODE" = "308" ]; then
      #       exit 0
      #     fi
      #     sleep 1
      #   done
      #   exit 1
      # '';
      Restart = "always";
      RestartSec = "5s";
      User = "homepage-dashboard";
      Group = "homepage-dashboard";
      WorkingDirectory = "/var/lib/homepage-machine";
      Environment = [
        "PORT=${toString config.ports.homepage-machine}"
        "HOMEPAGE_CONFIG_DIR=/var/lib/homepage-machine"
        "HOMEPAGE_BASEPATH=/home"
        "HOMEPAGE_ALLOWED_HOSTS=all"
      ];
      EnvironmentFile = [
        "-/var/lib/homepage/jellyfin.env"
        config.sops.templates."homepage.env".path
      ];
    };
  };

  sops.templates."homepage.env" = {
    content = ''
      HOMEPAGE_VAR_SONARR_KEY=${config.sops.placeholder."media/sonarr_api_key"}
      HOMEPAGE_VAR_RADARR_KEY=${config.sops.placeholder."media/radarr_api_key"}
      HOMEPAGE_VAR_PROWLARR_KEY=${config.sops.placeholder."media/prowlarr_api_key"}
      HOMEPAGE_VAR_LIDARR_KEY=${config.sops.placeholder."media/lidarr_api_key"}
      HOMEPAGE_VAR_JELLYSEERR_KEY=${config.sops.placeholder."media/jellyseerr_api_key"}
      HOMEPAGE_VAR_PASSWORD=${config.sops.placeholder."password"}
      HOMEPAGE_VAR_SABNZBD_KEY=${config.sops.placeholder."media/sabnzbd_api_key"}
      HOMEPAGE_VAR_GRAFANA_PASSWORD=${config.sops.placeholder."password"}
      HOMEPAGE_ALLOWED_HOSTS="all"
    '';
  };

  environment.etc."homepage-machine/settings.yaml".text = lib.generators.toYAML { } {
    title = "${config.networking.hostName} Dashboard";
    base = "/home";
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
          "Unmanic" = {
            href = "/unmanic/";
            icon = "unmanic.png";
            description = "Library Optimiser";
            widget = {
              type = "unmanic";
              url = "http://localhost:${toString config.ports.unmanic}";
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
  };

  services.traefik.proxies.homepage-machine-assets = {
    rule = "Host(`${fqdn}`) && (PathPrefix(`/_next`) || PathPrefix(`/images`) || PathPrefix(`/api/config`) || PathPrefix(`/icons`) || PathPrefix(`/site.webmanifest`))";
    target = "http://127.0.0.1:${toString config.ports.homepage-machine}";
  };
}
