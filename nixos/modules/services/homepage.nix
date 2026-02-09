{
  config,
  lib,
  ...
}:
let
  domain = "home.${config.networking.domain}";
in
{
  services.homepage-dashboard = {
    enable = lib.mkForce true;
    listenPort = config.ports.homepage;
    environmentFile = config.sops.templates."homepage.env".path;
    services = [
      {
        "Media" = [
          {
            "Jellyfin" = {
              href = "https://tv.${config.networking.domain}/jellyfin";
              icon = "jellyfin.png";
              description = "Media Server";
              widget = {
                type = "jellyfin";
                url = "https://tv.${config.networking.domain}/jellyfin";
                key = "{{HOMEPAGE_VAR_JELLYFIN_KEY}}";
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
              href = "https://tv.${config.networking.domain}/jellyseerr";
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
              href = "https://tv.${config.networking.domain}/sonarr";
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
              href = "https://tv.${config.networking.domain}/radarr";
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
            "Sonarr Anime" = {
              href = "https://tv.${config.networking.domain}/sonarr-anime";
              icon = "sonarr.png";
              description = "Anime";
              widget = {
                type = "sonarr";
                url = "http://localhost:${toString config.ports.sonarr-anime}";
                key = "{{HOMEPAGE_VAR_SONARR_KEY}}";
              };
            };
          }
          {
            "Prowlarr" = {
              href = "https://tv.${config.networking.domain}/prowlarr";
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
              href = "https://tv.${config.networking.domain}/lidarr";
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
              href = "https://tv.${config.networking.domain}/bazarr";
              icon = "bazarr.png";
              description = "Subtitles";
              # widget = {
              #  type = "bazarr";
              #  url = "http://localhost:${toString config.ports.bazarr}";
              #  key = "{{HOMEPAGE_VAR_BAZARR_KEY}}";
              # };
            };
          }
          {
            "qBittorrent" = {
              href = "https://tv.${config.networking.domain}/qbit";
              icon = "qbittorrent.png";
              description = "Torrent Client";
              widget = {
                type = "qbittorrent";
                url = "http://localhost:${toString config.ports.qbittorrent}";
                username = "i";
                password = "{{HOMEPAGE_VAR_PASSWORD}}";
                enableLeechProgress = false; # Download list
              };
            };
          }
          {
            "Vertex" = {
              href = "https://tv.${config.networking.domain}/vertex";
              icon = "vertex.png"; # Homepage will try to find it, or show default if missing
              description = "PT Manager";
            };
          }
          {
            "Autobrr" = {
              href = "https://tv.${config.networking.domain}/autobrr";
              icon = "autobrr.png";
              description = "Auto Downloader";
            };
          }
          {
            "Sabnzbd" = {
              href = "https://tv.${config.networking.domain}/sabnzbd";
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
        "Social" = [
          {
            "Mastodon" = {
              href = "https://zone.${config.networking.domain}";
              icon = "mastodon.png";
              description = "Social Network";
              widget = {
                type = "mastodon";
                url = "https://zone.${config.networking.domain}";
              };
            };
          }
          {
            "Element" = {
              href = "https://m.${config.networking.domain}";
              icon = "element.png";
              description = "Matrix Client";
            };
          }
          {
            "Matrix Admin" = {
              href = "https://admin.m.${config.networking.domain}";
              icon = "matrix.png";
              description = "Matrix Admin";
            };
          }
        ];
      }
      {
        "Tools" = [
          {
            "Traefik" = {
              href = "https://${config.networking.fqdn}/dashboard/";
              icon = "traefik.png";
              description = "Reverse Proxy";
            };
          }
          {
            "SearX" = {
              href = "https://searx.${config.networking.domain}";
              icon = "searxng.png";
              description = "Privacy Search";
            };
          }
          {
            "Grafana" = {
              href = "https://dash.${config.networking.domain}";
              icon = "grafana.png";
              description = "Monitoring";
              widget = {
                type = "grafana";
                url = "https://dash.${config.networking.domain}";
                username = "i";
                password = "{{HOMEPAGE_VAR_GRAFANA_PASSWORD}}";
              };
            };
          }
          {
            "Prometheus" = {
              href = "https://metrics.${config.networking.domain}";
              icon = "prometheus.png";
              description = "Metrics";
              widget = {
                type = "prometheusmetric";
                url = "http://localhost:${toString config.services.prometheus.port}";
                metrics = [
                  {
                    label = "Node CPU";
                    query = "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[1m])) * 100)";
                    format = {
                      type = "percent";
                    };
                  }
                  {
                    label = "Node Memory";
                    query = "(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100";
                    format = {
                      type = "percent";
                    };
                  }
                ];
              };
            };
          }
          {
            "Ntfy" = {
              href = "https://ntfy.${config.networking.domain}";
              icon = "ntfy.png";
              description = "Notification Service";
            };
          }
          {
            "Alist" = {
              href = "https://alist.${config.networking.domain}";
              icon = "alist.png";
              description = "File Listing";
            };
          }
          {
            "Vaultwarden" = {
              href = "https://vault.${config.networking.domain}";
              icon = "vaultwarden.png";
              description = "Password Manager";
            };
          }
          {
            "Code Server" = {
              href = "https://code.${config.networking.domain}";
              icon = "vscode.png";
              description = "VS Code";
            };
          }
          {
            "Reader" = {
              href = "https://reader.${config.networking.domain}";
              icon = "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/reader.png";
              description = "Book Reader";
            };
          }
          {
            "Syncthing" = {
              href = "https://${config.networking.fqdn}/syncthing";
              icon = "syncthing.png";
              description = "File Sync";
            };
          }
          {
            "CookieCloud" = {
              href = "https://cookie.${config.networking.domain}";
              icon = "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/cookiecloud.png";
              description = "Cookie Sync";
            };
          }
          {
            "Headscale" = {
              href = "https://ts.${config.networking.domain}";
              icon = "https://raw.githubusercontent.com/juanfont/headscale/main/docs/assets/logo/headscale3_header_stacked_left.png";
              description = "VPN Control";
            };
          }
          {
            "Keycloak" = {
              href = "https://sso.${config.networking.domain}";
              icon = "keycloak.png";
              description = "Authentication";
            };
          }
        ];
      }
    ];
    widgets = [
      {
        search = {
          provider = "custom";
          url = "https://searx.${config.networking.domain}/search?q=";
          suggestionUrl = "https://searx.${config.networking.domain}/autocomplete?type=list&q=";
          showSearchSuggestions = true;
          target = "_blank";
        };
      }
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
        openmeteo = {
          timezone = "Asia/Shanghai";
          units = "metric";
          cache = 5;
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
    settings = {
      title = "Dora Dashboard";
      background = {
        image = "https://images.unsplash.com/photo-1502790671504-542ad42d5189?auto=format&fit=crop&w=2560&q=80";
        blur = "sm"; # sm, "", md, xl... see https://tailwindcss.com/docs/backdrop-blur
        saturate = 50; # 0, 50, 100... see https://tailwindcss.com/docs/backdrop-saturate
        brightness = 50; # 0, 50, 75... see https://tailwindcss.com/docs/backdrop-brightness
      };
    };
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      homepage = {
        rule = "Host(`${domain}`)";
        entryPoints = [ "https" ];
        service = "homepage";
      };
    };
    services = {
      homepage.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://127.0.0.1:${toString config.ports.homepage}"; } ];
      };
    };
  };

  sops.templates."homepage.env" = {
    content = ''
      HOMEPAGE_VAR_SONARR_KEY=${config.sops.placeholder."media/sonarr_api_key"}
      HOMEPAGE_VAR_RADARR_KEY=${config.sops.placeholder."media/radarr_api_key"}
      HOMEPAGE_VAR_PROWLARR_KEY=${config.sops.placeholder."media/prowlarr_api_key"}
      HOMEPAGE_VAR_LIDARR_KEY=${config.sops.placeholder."media/lidarr_api_key"}
      HOMEPAGE_VAR_JELLYSEERR_KEY=${config.sops.placeholder."media/jellyseerr_api_key"}
      HOMEPAGE_VAR_JELLYFIN_KEY=${config.sops.placeholder."media/jellyfin_api_key"}
      HOMEPAGE_VAR_PASSWORD=${config.sops.placeholder."password"}
      HOMEPAGE_VAR_SABNZBD_KEY=${config.sops.placeholder."media/sabnzbd_api_key"}
      HOMEPAGE_VAR_GRAFANA_PASSWORD=${config.sops.placeholder."password"}
      HOMEPAGE_ALLOWED_HOSTS="home.dora.im,localhost,127.0.0.1"
    '';
  };
}
