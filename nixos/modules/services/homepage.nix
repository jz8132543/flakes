{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.networking) domain;
  media = rec {
    jellyfin = "https://jellyfin.${domain}/jellyfin";
    seerr = "https://seerr.${domain}";
    sonarr = "https://sonarr.${domain}";
    radarr = "https://radarr.${domain}";
    sonarrAnime = "https://sonarr-anime.${domain}";
    prowlarr = "https://prowlarr.${domain}";
    lidarr = "https://lidarr.${domain}";
    # bazarr = "https://bazarr.${domain}";
    qbit = "https://qbit.${domain}";
    vertex = "https://vertex.${domain}";
    autobrr = "https://autobrr.${domain}";
    navidrome = "https://navidrome.${domain}";
    maintainerr = "https://maintainerr.${domain}";
  };
in
{
  services.homepage-dashboard = {
    enable = lib.mkForce true;
    listenPort = config.ports.homepage;
    environmentFiles = [ config.sops.templates."homepage.env".path ];
    allowedHosts = "*";
    services = [
      {
        "Apps" = [
          {
            "Media" = [
              {
                "Jellyfin" = {
                  href = media.jellyfin;
                  icon = "jellyfin.png";
                  description = "Media Server";
                  widget = {
                    type = "jellyfin";
                    url = media.jellyfin;
                    key = "{{HOMEPAGE_VAR_JELLYFIN_GENERATED_KEY}}";
                    version = 2;
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
                    url = "https://seerr.${domain}";
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
                    url = "https://sonarr.${domain}/sonarr";
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
                    url = "https://radarr.${domain}/radarr";
                    key = "{{HOMEPAGE_VAR_RADARR_KEY}}";
                    enableQueue = true;
                  };
                };
              }
              {
                "Sonarr Anime" = {
                  href = media.sonarrAnime;
                  icon = "sonarr.png";
                  description = "Anime";
                  widget = {
                    type = "sonarr";
                    url = "https://sonarr-anime.${domain}/sonarr-anime";
                    key = "{{HOMEPAGE_VAR_SONARR_KEY}}";
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
                    url = "https://prowlarr.${domain}/prowlarr";
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
                    url = "https://lidarr.${domain}/lidarr";
                    key = "{{HOMEPAGE_VAR_LIDARR_KEY}}";
                  };
                };
              }
              # {
              #   "Bazarr" = {
              #     href = media.bazarr;
              #     icon = "bazarr.png";
              #     description = "Subtitles";
              #   };
              # }
              {
                "qBittorrent" = {
                  href = media.qbit;
                  icon = "qbittorrent.png";
                  description = "Torrent Client";
                  widget = {
                    type = "qbittorrent";
                    url = media.qbit;
                    username = "i";
                    password = "{{HOMEPAGE_VAR_PASSWORD}}";
                    enableLeechProgress = false; # Download list
                  };
                };
              }
              {
                "Vertex" = {
                  href = media.vertex;
                  icon = "https://cdn.jsdelivr.net/gh/vertex-app/vertex@stable/webui/public/assets/images/logo.svg";
                  description = "PT Manager";
                };
              }
              {
                "autobrr" = {
                  href = media.autobrr;
                  icon = "autobrr.png";
                  description = "Auto Downloader";
                };
              }
              {
                "Navidrome" = {
                  href = media.navidrome;
                  icon = "navidrome.png";
                  description = "Music Streamer";
                  widget = {
                    type = "navidrome";
                    url = media.navidrome;
                    user = "i"; # your username
                    salt = "doraemon";
                    token = "{{HOMEPAGE_VAR_NAVIDROME_TOKEN}}";
                  };
                };
              }
              {
                "Maintainerr" = {
                  href = media.maintainerr;
                  icon = "maintainerr.png";
                  description = "Media Maintenance";
                };
              }
              {
                "Flaresolverr" = {
                  icon = "flaresolverr.png";
                  description = "Cloudflare Proxy";
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
        ];
      }
      {
        "Tools" = [
          {
            "Traefik" = {
              href = "https://${config.networking.fqdn}/dashboard/";
              icon = "traefik.png";
              description = "Reverse Proxy";
              widget = {
                type = "prometheusmetric";
                url = "https://metrics.${config.networking.domain}";
                username = "i";
                password = "{{HOMEPAGE_VAR_PASSWORD}}";
                metrics = [
                  {
                    label = "Req/s";
                    query = "sum(rate(traefik_entrypoint_requests_total[1m]))";
                    format = {
                      type = "number";
                      options = {
                        maximumFractionDigits = 2;
                      };
                    };
                  }
                  {
                    label = "Errors/s";
                    query = "sum(rate(traefik_entrypoint_requests_total{code!~\"2..\"}[1m]))";
                    format = {
                      type = "number";
                      options = {
                        maximumFractionDigits = 2;
                      };
                    };
                  }
                ];
              };
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
            "VictoriaMetrics" = {
              href = "https://metrics.${config.networking.domain}";
              icon = "victoriametrics.png";
              description = "Metrics";
              widget = {
                type = "prometheusmetric";
                url = "https://metrics.${config.networking.domain}";
                username = "i";
                password = "{{HOMEPAGE_VAR_PASSWORD}}";
                metrics = [
                  {
                    label = "CPU Usage";
                    query = "100 - (avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)";
                    format = {
                      type = "percent";
                    };
                  }
                  {
                    label = "Memory Usage";
                    query = "(sum(node_memory_MemTotal_bytes) - sum(node_memory_MemAvailable_bytes)) / sum(node_memory_MemTotal_bytes) * 100";
                    format = {
                      type = "percent";
                    };
                  }
                  {
                    label = "Disk Usage";
                    query = "100 - ((sum(node_filesystem_avail_bytes{mountpoint=\"/\",fstype!=\"rootfs\"}) * 100) / sum(node_filesystem_size_bytes{mountpoint=\"/\",fstype!=\"rootfs\"}))";
                    format = {
                      type = "percent";
                    };
                  }
                ];
              };
            };
          }
          {
            "PostgreSQL" = {
              icon = "postgresql.png";
              description = "Database";
              widget = {
                type = "prometheusmetric";
                url = "https://metrics.${config.networking.domain}";
                username = "i";
                password = "{{HOMEPAGE_VAR_PASSWORD}}";
                metrics = [
                  {
                    label = "Connections";
                    query = "sum(pg_stat_database_numbackends)";
                    format = {
                      type = "number";
                    };
                  }
                  {
                    label = "Transactions/sec";
                    query = "sum(irate(pg_stat_database_xact_commit[5m]))";
                    format = {
                      type = "number";
                      options = {
                        maximumFractionDigits = 2;
                      };
                    };
                  }
                ];
              };
            };
          }
          {
            "Degoog" = {
              href = "https://search.${config.networking.domain}";
              icon = "si-google";
              description = "Privacy Search Aggregator";
            };
          }
          {
            "Ntfy" = {
              href = "https://ntfy.${config.networking.domain}";
              icon = "ntfy.png";
              description = "Notification Service";
              widget = {
                type = "ntfy";
                url = "https://ntfy.${config.networking.domain}";
                topic = "alerts";
                username = "i";
                password = "{{HOMEPAGE_VAR_PASSWORD}}";
              };
            };
          }
          {
            "Nextcloud" = {
              href = "https://cloud.${domain}";
              icon = "nextcloud.png";
              description = "Cloud Storage";
              widget = {
                type = "nextcloud";
                url = "https://cloud.${domain}";
                key = "{{HOMEPAGE_VAR_NEXTCLOUD_TOKEN}}";
              };
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
              widget = {
                type = "syncthing";
                url = "https://${config.networking.fqdn}/syncthing";
                key = "{{HOMEPAGE_VAR_SYNCTHING_KEY}}";
              };
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
            "Keycloak" = {
              href = "https://sso.${config.networking.domain}";
              icon = "keycloak.png";
              description = "Authentication";
            };
          }
          {
            "Grimmory" = {
              href = "https://book.${config.networking.domain}";
              icon = "booklore.png";
              description = "Digital Library";
            };
          }
          {
            "Linkwarden" = {
              href = "https://link.${config.networking.domain}";
              icon = "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/linkwarden.png";
              description = "Bookmarks";
            };
          }
          {
            "Pastebin" = {
              href = "https://pb.${config.networking.domain}";
              icon = "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/microbin.png";
              description = "Paste Service";
            };
          }
          {
            "AdGuard Home" = {
              href = "https://dns.${domain}";
              icon = "adguard-home.png";
              description = "DNS & Ad Blocker";
              widget = {
                type = "adguard";
                url = "https://dns.${domain}";
                username = "i";
                password = "{{HOMEPAGE_VAR_PASSWORD}}";
              };
            };
          }
          {
            "Headscale" = {
              href = "https://ts.${domain}";
              icon = "https://raw.githubusercontent.com/juanfont/headscale/main/docs/assets/logo/headscale3_header_stacked_left.png";
              description = "Tailscale Control Server";
              widget = {
                type = "headscale";
                url = "https://ts.${domain}";
                key = "{{HOMEPAGE_VAR_HEADSCALE_KEY}}";
                nodeId = 456;
              };
            };
          }
        ];
      }
    ];
    widgets = [
      {
        search = {
          provider = "custom";
          url = "https://search.${config.networking.domain}/search?q=";
          suggestionUrl = "https://search.${config.networking.domain}/api/suggest?q=";
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
        datetime = {
          format = {
            timeStyle = "short";
          };
        };
      }
    ];
    settings = {
      title = "Doraemon's Dashboard";
      background = {
        image = "https://images.unsplash.com/photo-1502790671504-542ad42d5189?auto=format&fit=crop&w=2560&q=80";
        blur = "sm"; # sm, "", md, xl... see https://tailwindcss.com/docs/backdrop-blur
        saturate = 50; # 0, 50, 100... see https://tailwindcss.com/docs/backdrop-saturate
        brightness = 50; # 0, 50, 75... see https://tailwindcss.com/docs/backdrop-brightness
      };
      # Layout: Set groups to be side-by-side (left: Apps [Media + Social], right: Tools)
      layout = {
        "Apps" = {
          header = false;
          "Media" = {
            header = true;
            style = "row";
            columns = 1;
          };
          "Social" = {
            header = true;
            style = "row";
            columns = 1;
          };
        };
        "Tools" = {
          header = true;
          style = "row";
          columns = 1;
        };
      };
    };
    customCSS = ''
      #services > .services-group:not(.subgroup),
      #layout-groups > .services-group:not(.subgroup) {
        flex-basis: 50% !important;
        max-width: 50% !important;
      }
      @media (max-width: 768px) {
        #services > .services-group:not(.subgroup),
        #layout-groups > .services-group:not(.subgroup) {
          flex-basis: 100% !important;
          max-width: 100% !important;
        }
      }
    '';
  };

  services.traefik.proxies.homepage = {
    rule = "Host(`${domain}`)";
    target = "http://127.0.0.1:${toString config.ports.homepage}";
    # priority = 10;
    # We don't need entryPoints/loadBalancer because proxies handles it
  };

  systemd.services.homepage-navidrome-env = {
    description = "Generate Navidrome ENV for Homepage";
    wantedBy = [
      "homepage-dashboard.service"
      "multi-user.target"
    ];
    before = [ "homepage-dashboard.service" ];
    script = ''
      set -e
      mkdir -p /var/lib/homepage
      PASSWORD=$(cat ${config.sops.secrets."password".path})
      SALT="doraemon"
      # md5sum outputs hash followed by a space and a dash
      TOKEN=$(echo -n "''${PASSWORD}''${SALT}" | ${pkgs.coreutils}/bin/md5sum | ${pkgs.gawk}/bin/awk '{print $1}')
      echo "HOMEPAGE_VAR_NAVIDROME_TOKEN=''${TOKEN}" > /var/lib/homepage/navidrome.env
      chmod 644 /var/lib/homepage/navidrome.env

      if [ -f /var/lib/syncthing/.config/syncthing/config.xml ]; then
        SYNCTHING_KEY=$(${pkgs.gnused}/bin/sed -n 's/.*<apikey>\(.*\)<\/apikey>.*/\1/p' /var/lib/syncthing/.config/syncthing/config.xml | head -n 1)
        echo "HOMEPAGE_VAR_SYNCTHING_KEY=''${SYNCTHING_KEY}" > /var/lib/homepage/syncthing.env
        chmod 644 /var/lib/homepage/syncthing.env
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };

  # Load generated env file (ignore if missing with - prefix)
  systemd.services.homepage-dashboard = {
    wants = [ "homepage-navidrome-env.service" ];
    serviceConfig.EnvironmentFile = lib.mkAfter [
      "-/var/lib/homepage/jellyfin.env"
      "-/var/lib/homepage/navidrome.env"
      "-/var/lib/homepage/syncthing.env"
    ];
  };

  sops.templates."homepage.env" = {
    content = ''
      HOMEPAGE_VAR_SONARR_KEY=${config.sops.placeholder."media/sonarr_api_key"}
      HOMEPAGE_VAR_RADARR_KEY=${config.sops.placeholder."media/radarr_api_key"}
      HOMEPAGE_VAR_PROWLARR_KEY=${config.sops.placeholder."media/prowlarr_api_key"}
      HOMEPAGE_VAR_LIDARR_KEY=${config.sops.placeholder."media/lidarr_api_key"}
      HOMEPAGE_VAR_JELLYSEERR_KEY=${config.sops.placeholder."media/jellyseerr_api_key"}
      HOMEPAGE_VAR_JELLYFIN_GENERATED_KEY=${config.sops.placeholder."media/jellyfin_api_key"}
      HOMEPAGE_VAR_PASSWORD=${config.sops.placeholder."password"}
      HOMEPAGE_VAR_GRAFANA_PASSWORD=${config.sops.placeholder."password"}
      HOMEPAGE_VAR_HEADSCALE_KEY=${config.sops.placeholder."homepage/headscale_key"}
      HOMEPAGE_VAR_NEXTCLOUD_TOKEN=${config.sops.placeholder."homepage/nextcloud_token"}
    '';
  };

  sops.secrets."homepage/headscale_key" = { };
  sops.secrets."homepage/nextcloud_token" = { };
}
