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
  # Use a manual systemd service because the homepage-dashboard module only supports one instance
  systemd.services.homepage-machine = {
    description = "Homepage Dashboard (Machine Specific)";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.homepage-dashboard}/bin/homepage-dashboard";
      Restart = "always";
      User = "homepage-dashboard";
      Group = "homepage-dashboard";
      Environment = [
        "PORT=${toString config.ports.homepage-machine}"
        "HOMEPAGE_CONFIG_DIR=/etc/homepage-machine"
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
      HOMEPAGE_ALLOWED_HOSTS="${config.networking.domain},${config.networking.fqdn},localhost,127.0.0.1"
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

  services.traefik.dynamicConfigOptions.http = {
    middlewares = {
      strip-home = {
        stripPrefix = {
          prefixes = [ "/home" ];
        };
      };
    };
    routers = {
      homepage-machine = {
        rule = "Host(`${fqdn}`) && (Path(`/home`) || PathPrefix(`/home/`))";
        entryPoints = [ "https" ];
        service = "homepage-machine";
        middlewares = [ "strip-home" ];
      };
    };
    services = {
      homepage-machine.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://127.0.0.1:${toString config.ports.homepage-machine}"; } ];
      };
    };
  };
}
