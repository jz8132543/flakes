# Reference: https://github.com/masood09/nix/blob/e43e3928dc919603b2a2c31a43b0a9d1bfbd9ba8/modules/services/arr/default.nix#L339
{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:
let
  inherit (config.networking) domain fqdn;

  # Public external URLs centralized in options.nixflix.urls for consistency, DRY, and cross-module reuse
  externalUrls = config.nixflix.urls;

  # Shared media authentication configuration (Forms auth with SOPS password)
  commonHostConfig = {
    username = "i";
    password._secret = config.sops.secrets."password".path;
  };

  # Helper for Seerr Radarr instance configuration
  mkSeerrRadarrInstance =
    {
      cfg,
      externalUrl,
      activeProfileName ? "SQP-1 (1080p)",
      isDefault ? true,
    }:
    {
      hostname = cfg.connectionAddress;
      port = cfg.config.hostConfig.port or 7878;
      inherit (cfg.config) apiKey;
      baseUrl = cfg.config.hostConfig.urlBase;
      activeDirectory = builtins.head (cfg.mediaDirs or [ "/data/media/movies" ]);
      inherit isDefault externalUrl activeProfileName;
    };

  # Helper for Seerr Sonarr instance configuration
  mkSeerrSonarrInstance =
    {
      cfg,
      externalUrl,
      activeProfileName ? "WEB-1080p",
      isAnime ? false,
      isDefault ? true,
    }:
    {
      hostname = cfg.connectionAddress;
      port = cfg.config.hostConfig.port or 8989;
      inherit (cfg.config) apiKey;
      baseUrl = cfg.config.hostConfig.urlBase;
      activeDirectory = builtins.head (cfg.mediaDirs or [ "/data/media/tv" ]);
      activeAnimeDirectory = builtins.head (cfg.mediaDirs or [ "/data/media/tv" ]);
      seriesType = "standard";
      animeSeriesType = if isAnime then "anime" else "standard";
      inherit isDefault externalUrl activeProfileName;
    };

  # Helper for Prowlarr application registration
  mkProwlarrApp =
    {
      name,
      implementationName,
      cfg,
    }:
    {
      inherit name implementationName;
      inherit (cfg.config) apiKey;
      baseUrl = "http://127.0.0.1:${toString cfg.config.hostConfig.port}${cfg.config.hostConfig.urlBase}";
      prowlarrUrl = "http://127.0.0.1:${toString config.ports.prowlarr}/prowlarr";
    };

  # Helper for Traefik proxy definitions
  mkProxy = subdomain: port: {
    rule = "Host(`${subdomain}.${domain}`) || Host(`${subdomain}.${fqdn}`)";
    target = "http://127.0.0.1:${toString port}";
  };
in
{
  imports = [ inputs.nixflix.nixosModules.default ];

  options.nixflix.urls = {
    jellyfin = lib.mkOption {
      type = lib.types.str;
      default = "https://jellyfin.${domain}/jellyfin";
      description = "Public external URL for Jellyfin.";
    };
    qbit = lib.mkOption {
      type = lib.types.str;
      default = "https://qbit.${domain}";
      description = "Public external URL for qBittorrent.";
    };
    seerr = lib.mkOption {
      type = lib.types.str;
      default = "https://seerr.${domain}";
      description = "Public external URL for Seerr.";
    };
    sonarr = lib.mkOption {
      type = lib.types.str;
      default = "https://sonarr.${domain}/sonarr";
      description = "Public external URL for Sonarr.";
    };
    sonarr-anime = lib.mkOption {
      type = lib.types.str;
      default = "https://sonarr-anime.${domain}/sonarr-anime";
      description = "Public external URL for Sonarr Anime.";
    };
    radarr = lib.mkOption {
      type = lib.types.str;
      default = "https://radarr.${domain}/radarr";
      description = "Public external URL for Radarr.";
    };
    prowlarr = lib.mkOption {
      type = lib.types.str;
      default = "https://prowlarr.${domain}/prowlarr";
      description = "Public external URL for Prowlarr.";
    };
    lidarr = lib.mkOption {
      type = lib.types.str;
      default = "https://lidarr.${domain}/lidarr";
      description = "Public external URL for Lidarr.";
    };
  };

  config = {
    # Reuse official media hostnames consistently across routing and portals.
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
      postgres.enable = true;

      sonarr = {
        enable = true;
        group = "media";
        config = {
          apiKey._secret = config.sops.secrets."media/sonarr_api_key".path;
          hostConfig = commonHostConfig // {
            urlBase = "/sonarr";
            applicationUrl = externalUrls.sonarr;
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
          apiKey._secret = config.sops.secrets."media/radarr_api_key".path;
          hostConfig = commonHostConfig // {
            urlBase = "/radarr";
            applicationUrl = externalUrls.radarr;
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
          apiKey._secret = config.sops.secrets."media/prowlarr_api_key".path;
          hostConfig = commonHostConfig // {
            urlBase = "/prowlarr";
            applicationUrl = externalUrls.prowlarr;
          };
          applications = [
            (mkProwlarrApp {
              name = "Sonarr";
              implementationName = "Sonarr";
              cfg = config.nixflix.sonarr;
            })
            (mkProwlarrApp {
              name = "Radarr";
              implementationName = "Radarr";
              cfg = config.nixflix.radarr;
            })
            (mkProwlarrApp {
              name = "Lidarr";
              implementationName = "Lidarr";
              cfg = config.nixflix.lidarr;
            })
            (mkProwlarrApp {
              name = "Sonarr Anime";
              implementationName = "Sonarr";
              cfg = config.nixflix.sonarr-anime;
            })
          ];
          indexers = [
            {
              name = "M-Team - TP";
              enable = true;
              implementationName = "Gazelle";
              baseUrl = "https://kp.m-team.cc/";
              apiKey._secret = config.sops.secrets."media/mteam_api_key".path;
            }
          ];
        };
      };

      lidarr = {
        enable = true;
        group = "media";
        config = {
          apiKey._secret = config.sops.secrets."media/lidarr_api_key".path;
          hostConfig = commonHostConfig // {
            urlBase = "/lidarr";
            applicationUrl = externalUrls.lidarr;
          };
        };
      };

      recyclarr = {
        enable = true;
        group = "media";
        cleanupUnmanagedProfiles.enable = true;
      };

      seerr = {
        enable = true;
        jellyfin = {
          adminUsername = "i";
          adminPassword._secret = config.sops.secrets."password".path;
          externalHostname = externalUrls.jellyfin;
        };
        settings.users.defaultPermissions = 1024;
        apiKey._secret = config.sops.secrets."media/jellyseerr_api_key".path;

        radarr.Radarr = mkSeerrRadarrInstance {
          cfg = config.nixflix.radarr;
          externalUrl = externalUrls.radarr;
          activeProfileName = "SQP-1 (1080p)";
        };

        sonarr = {
          Sonarr = mkSeerrSonarrInstance {
            cfg = config.nixflix.sonarr;
            externalUrl = externalUrls.sonarr;
            activeProfileName = "WEB-1080p";
            isDefault = true;
          };
          "Sonarr Anime" = mkSeerrSonarrInstance {
            cfg = config.nixflix.sonarr-anime;
            externalUrl = externalUrls.sonarr-anime;
            activeProfileName = "[Anime] Remux-1080p";
            isAnime = true;
            isDefault = false;
          };
        };
      };

      sonarr-anime = {
        enable = true;
        group = "media";
        config = {
          apiKey._secret = config.sops.secrets."media/sonarr_api_key".path;
          hostConfig = commonHostConfig // {
            urlBase = "/sonarr-anime";
            applicationUrl = externalUrls.sonarr-anime;
          };
          rootFolders = [
            { path = "/data/media/anime"; }
          ];
        };
      };

      jellyfin = {
        plugins."TheTVDB" = {
          enable = true;
          package = (inputs.nixflix.lib.buildJellyfinPlugin { inherit pkgs; }) {
            pname = "TheTVDB";
            version = "22.0.0.0";
            src = pkgs.fetchzip {
              url = "https://repo.jellyfin.org/releases/plugin/thetvdb/thetvdb_22.0.0.0.zip";
              hash = "sha256-X7XDq1rdwg5WrueKMI2NmZYvBGe0yzqe3QfF69+qgyE=";
              stripRoot = false;
            };
            passthru.pluginDirName = "TheTVDB_22.0.0.0";
          };
        };

        libraries = {
          Shows.typeOptions = lib.mkForce [
            {
              type = "Series";
              imageFetchers = [
                "TheTVDB"
                "TheMovieDb"
              ];
              imageFetcherOrder = [
                "TheTVDB"
                "TheMovieDb"
              ];
              metadataFetchers = [
                "TheTVDB"
                "TheMovieDb"
                "The Open Movie Database"
              ];
              metadataFetcherOrder = [
                "TheTVDB"
                "TheMovieDb"
                "The Open Movie Database"
              ];
            }
            {
              type = "Season";
              imageFetchers = [
                "TheTVDB"
                "TheMovieDb"
              ];
              imageFetcherOrder = [
                "TheTVDB"
                "TheMovieDb"
              ];
              metadataFetchers = [
                "TheTVDB"
                "TheMovieDb"
              ];
              metadataFetcherOrder = [
                "TheTVDB"
                "TheMovieDb"
              ];
            }
            {
              type = "Episode";
              # 仅使用网络元数据和海报源，移除本地截屏提取器 (Screen Grabber / Embedded Image Extractor)，彻底避免导入时 ffmpeg 跑满 CPU
              imageFetchers = [
                "TheTVDB"
                "TheMovieDb"
                "The Open Movie Database"
              ];
              imageFetcherOrder = [
                "TheTVDB"
                "TheMovieDb"
                "The Open Movie Database"
              ];
              metadataFetchers = [
                "TheTVDB"
                "TheMovieDb"
                "The Open Movie Database"
              ];
              metadataFetcherOrder = [
                "TheTVDB"
                "TheMovieDb"
                "The Open Movie Database"
              ];
            }
          ];

          Anime.typeOptions = lib.mkForce [
            {
              type = "Series";
              imageFetchers = [
                "TheTVDB"
                "AniDB"
                "AniSearch"
                "TheMovieDb"
              ];
              imageFetcherOrder = [
                "TheTVDB"
                "AniDB"
                "AniSearch"
                "TheMovieDb"
              ];
              metadataFetchers = [
                "TheTVDB"
                "AniDB"
                "AniSearch"
                "TheMovieDb"
                "The Open Movie Database"
              ];
              metadataFetcherOrder = [
                "TheTVDB"
                "AniDB"
                "AniSearch"
                "TheMovieDb"
                "The Open Movie Database"
              ];
            }
            {
              type = "Season";
              imageFetchers = [
                "TheTVDB"
                "TheMovieDb"
              ];
              imageFetcherOrder = [
                "TheTVDB"
                "TheMovieDb"
              ];
              metadataFetchers = [
                "TheTVDB"
                "TheMovieDb"
              ];
              metadataFetcherOrder = [
                "TheTVDB"
                "TheMovieDb"
              ];
            }
            {
              type = "Episode";
              # 仅使用网络元数据和海报源，移除本地截屏提取器 (Screen Grabber / Embedded Image Extractor)，彻底避免导入时 ffmpeg 跑满 CPU
              imageFetchers = [
                "TheTVDB"
                "AniDB"
                "TheMovieDb"
                "The Open Movie Database"
              ];
              imageFetcherOrder = [
                "TheTVDB"
                "AniDB"
                "TheMovieDb"
                "The Open Movie Database"
              ];
              metadataFetchers = [
                "TheTVDB"
                "AniDB"
                "TheMovieDb"
                "The Open Movie Database"
              ];
              metadataFetcherOrder = [
                "TheTVDB"
                "AniDB"
                "TheMovieDb"
                "The Open Movie Database"
              ];
            }
          ];
        };
      };

      flaresolverr = {
        enable = true;
      };

      navidrome = {
        enable = true;
        group = "media";
        users."i" = {
          userName = "i";
          isAdmin = true;
          password._secret = config.sops.secrets."password".path;
        };
      };

      maintainerr = {
        enable = true;
        group = "media";
      };
    };

    services.traefik.proxies = {
      jellyfin = mkProxy "jellyfin" config.ports.jellyfin;
      jellyseerr = mkProxy "seerr" config.ports.jellyseerr;
      navidrome = mkProxy "navidrome" config.ports.navidrome;
      maintainerr = mkProxy "maintainerr" config.ports.maintainerr;
      sonarr = mkProxy "sonarr" config.ports.sonarr;
      sonarr-anime = mkProxy "sonarr-anime" config.ports.sonarr-anime;
      radarr = mkProxy "radarr" config.ports.radarr;
      prowlarr = mkProxy "prowlarr" config.ports.prowlarr;
      lidarr = mkProxy "lidarr" config.ports.lidarr;
      autobrr = mkProxy "autobrr" config.ports.autobrr;
      bazarr = mkProxy "bazarr" config.ports.bazarr;
      qbittorrent = mkProxy "qbit" config.ports.qbittorrent;
      whoami = {
        rule = "Host(`${fqdn}`) && PathPrefix(`/whoami`)";
        target = "http://127.0.0.1:8082";
        middlewares = [ "strip-prefix" ];
      };
    };

    nixflix.torrentClients.qbittorrent = {
      enable = true;
      password._secret = config.sops.secrets."password".path;
      webuiPort = config.ports.qbittorrent;
      downloadsDir = "/data/downloads/torrents";
      categories = {
        movies = "/data/downloads/torrents/movies-radarr";
        tv = "/data/downloads/torrents/tv-sonarr";
        music = "/data/downloads/torrents/music-lidarr";
        prowlarr = "/data/downloads/torrents/prowlarr";
      };
      serverConfig = {
        LegalNotice.Accepted = true;
        Application = {
          FileLogger = {
            Age = 7;
            AgeType = 0;
            Backup = true;
            DeleteOld = true;
            Enabled = true;
            MaxSizeBytes = 66560;
            Path = "/var/lib/qBittorrent/qBittorrent/data/logs";
          };
          MemoryWorkingSetLimit = 4096;
        };
        BitTorrent = {
          Session = {
            DefaultSavePath = "/data/downloads/torrents/default";
            TempPath = "/data/downloads/torrents/.incomplete";
            TempPathEnabled = true;
            AddExtensionToIncompleteFiles = true; # Optimized for PT
            uTPRateLimited = true; # Optimized for PT
            BTProtocol = "Both";
            MaxConnections = 4000;
            MaxConnectionsPerTorrent = 500;
            MaxUploads = 200;
            MaxUploadsPerTorrent = 50;
            EnableSuperSeeding = false;
            ChokingAlgorithm = "FixedSlots";
            SeedChokingAlgorithm = "FastestUpload";
            UploadSlotsBehavior = "FixedSlots";
            AllowMultipleConnectionsFromSameIP = true;
            QueueingSystemEnabled = false; # Optimized for PT
            MaxActiveDownloads = 20;
            MaxActiveUploads = 100;
            MaxActiveTorrents = 120;
            AnnounceToAllTrackers = true;
            AnnounceToAllTiers = true;
            TrackerExchangeEnabled = true;
            Encryption = 1;
            AnonymousMode = false; # Set to false for better PT compatibility
            DHTEnabled = false;
            PeXEnabled = false;
            LSDEnabled = false;
            Port = 51413;
          };
        };
        AutoRun = {
          OnTorrentAdded = {
            Enabled = config.environment.seedbox.enable;
            Program = lib.mkIf config.environment.seedbox.enable "${pkgs.curl}/bin/curl -s -X POST \"http://localhost:${toString config.ports.qbittorrent}/api/v2/torrents/setUploadLimit\" -d \"hashes=%I&limit=41943040\"";
          };
        };
        Network = {
          Proxy = {
            Type = if config.environment.seedbox.enable then "SOCKS5" else "None";
            IP = if config.environment.seedbox.enable then config.environment.seedbox.proxyHost else "";
            Port = if config.environment.seedbox.enable then config.environment.seedbox.proxyPort else 8080;
            HostnameLookupEnabled = config.environment.seedbox.enable;
            Profiles = {
              BitTorrent = config.environment.seedbox.enable;
              RSS = config.environment.seedbox.enable;
              Misc = config.environment.seedbox.enable;
            };
          };
        };
        Preferences = {
          WebUI = {
            AlternativeUIEnabled = true;
            RootFolder = "${pkgs.vuetorrent}/share/vuetorrent";
            Username = "i";
            Password_PBKDF2 = "VoAtU+aAIMY35v/N0pKumg==:TBz/gyQ80z2x7L1ZtpnfHnEh3/y0OQ+zgD8dHbqaImmVmqnguQtPfR4VVmhGLxVN1XB8pWwYYwQHR3fyfWpGgg==";
            CSRFProtection = false;
            HostHeaderValidation = false;
            ServerDomains = "*";
            SecureCookie = false;
            ClickjackingProtection = false;
            LocalHostAuth = false;
            AuthSubnetWhitelistEnabled = false;
            AuthSubnetWhitelist = "127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16";
            ReverseProxySupportEnabled = true;
            TrustedReverseProxiesList = "127.0.0.1";
          };

          Downloads = {
            SavePath = "/data/downloads/torrents";
            TempPath = "/data/downloads/torrents/.incomplete";
            TempPathEnabled = true;
          };
          Connection = {
            GlobalMaxConnections = 4000;
            MaxConnectionsPerTorrent = 500;
            GlobalMaxUploads = 200;
            MaxUploadsPerTorrent = 50;
            PortRangeMin = 51413;
          };
          General = {
            Locale = "zh_CN";
          };
        };
        RSS = {
          AutoDownloader = {
            DownloadRepacks = true;
            SmartEpisodeFilter = ''
              s(\\d+)e(\\d+), (\\d+)x(\\d+), "(\\d{4}[.\\-]\\d{1,2}[.\\-]\\d{1,2})", "(\\d{1,2}[.\\-]\\d{1,2}[.\\-]\\d{4})"
            '';
          };
        };
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
              "seerr"
              "sonarr"
              "radarr"
              "prowlarr"
              "lidarr"
              "flaresolverr"
              "navidrome"
              "maintainerr"
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
              "seerr-setup"
              "seerr-user-settings"
              "seerr-jellyfin"
              "seerr-libraries"
              "seerr-sonarr"
              "seerr-radarr"
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
          qbit-ip-reporter = lib.mkIf config.environment.seedbox.enable {
            description = "Report qBittorrent public IP to tracker";
            after = [ "qbittorrent.service" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart =
                let
                  script = pkgs.writeShellScript "qbit-ip-reporter.sh" ''
                    CURRENT_IP=$(${pkgs.curl}/bin/curl -fsS --max-time 10 https://api.ipify.org || true)
                    if [ -z "$CURRENT_IP" ]; then
                      echo "Failed to get public IP, skipping qBittorrent announce_ip update"
                      exit 0
                    fi

                    until ${pkgs.curl}/bin/curl -s "http://localhost:${toString config.ports.qbittorrent}" > /dev/null; do
                      echo "Waiting for qBittorrent WebUI..."
                      sleep 2
                    done

                    ${pkgs.curl}/bin/curl -i -X POST "http://localhost:${toString config.ports.qbittorrent}/api/v2/app/setPreferences" \
                      -d "json={\"announce_ip\":\"$CURRENT_IP\"}"
                  '';
                in
                "${script}";
              User = "qbittorrent";
            };
          };

          qbittorrent.serviceConfig = {
            DynamicUser = lib.mkForce false;
            User = lib.mkForce "qbittorrent";
            Group = lib.mkForce "media";
            StateDirectory = lib.mkForce "";
            WorkingDirectory = lib.mkForce "/var/lib/qBittorrent";
            LimitNOFILE = lib.mkForce 16384;
            MemoryDenyWriteExecute = lib.mkForce false;
            RestrictAddressFamilies = lib.mkForce "AF_UNIX AF_INET AF_INET6 AF_NETLINK";
            Environment = lib.mkForce "LOCALE_ARCHIVE=/run/current-system/sw/lib/locale/locale-archive";
            Restart = "always";
            RestartSec = "5s";
            ProtectHome = lib.mkForce false;
            ProtectSystem = lib.mkForce false;
            PrivateTmp = lib.mkForce false;
            NoNewPrivileges = lib.mkForce false;
            SystemCallFilter = lib.mkForce [ ];
            ProtectProc = lib.mkForce "default";
            ProcSubset = lib.mkForce "all";
            UMask = "0002";
            CPUSchedulingPolicy = "idle";
            IOSchedulingClass = "idle";
            IPQoS = "background";
          };

          sonarr.serviceConfig.UMask = lib.mkForce "0002";
          radarr.serviceConfig.UMask = lib.mkForce "0002";
          prowlarr.serviceConfig.UMask = lib.mkForce "0002";
          lidarr.serviceConfig.UMask = lib.mkForce "0002";
          seerr = {
            serviceConfig.UMask = lib.mkForce "0002";
            wants = [
              "seerr-setup.service"
              "seerr-user-settings.service"
              "seerr-jellyfin.service"
              "seerr-libraries.service"
              "seerr-sonarr.service"
              "seerr-radarr.service"
            ];
          };
          sonarr-anime.serviceConfig.UMask = lib.mkForce "0002";
          navidrome = {
            serviceConfig.UMask = lib.mkForce "0002";
            wants = [
              "navidrome-create-admin.service"
              "navidrome-users-config.service"
            ];
          };
          maintainerr.serviceConfig.UMask = lib.mkForce "0002";
        };

      timers.qbit-ip-reporter = lib.mkIf config.environment.seedbox.enable {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "1min";
          OnUnitActiveSec = "10min";
        };
      };

      tmpfiles.rules = [
        "Z /data/downloads/torrents 0777 qbittorrent media -"
        "Z /data/downloads/torrents/.incomplete 0777 qbittorrent media -"
        "Z /data/downloads/torrents/tv-sonarr 0777 qbittorrent media -"
        "Z /data/downloads/torrents/sonarr-anime 0777 qbittorrent media -"
        "Z /data/downloads/torrents/movies-radarr 0777 qbittorrent media -"
        "Z /data/downloads/torrents/music-lidarr 0777 qbittorrent media -"
        "Z /data/downloads/torrents/prowlarr 0777 qbittorrent media -"
        "Z /data/torrents 0777 qbittorrent media -"
        "Z /data/torrents/downloading 0777 qbittorrent media -"
        "Z /data/torrents/completed 0777 qbittorrent media -"
        "Z /var/lib/qBittorrent 0777 qbittorrent media -"
      ];
    };

    environment.global-persistence.directories = [
      "/var/lib/qbittorrent"
    ];

    networking.firewall = {
      allowedTCPPorts = [ 51413 ];
      allowedUDPPorts = [ 51413 ];
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
