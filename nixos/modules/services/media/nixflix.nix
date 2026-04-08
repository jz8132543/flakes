{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:
{
  imports = [ inputs.nixflix.nixosModules.default ];

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
      postgres.enable = false;

      sonarr = {
        enable = true;
        group = "media";
        config = {
          apiKey._secret = config.sops.secrets."media/sonarr_api_key".path;
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
          apiKey._secret = config.sops.secrets."media/radarr_api_key".path;
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
          apiKey._secret = config.sops.secrets."media/prowlarr_api_key".path;
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
              apiKey._secret = config.sops.secrets."media/sonarr_api_key".path;
              baseUrl = "http://127.0.0.1:${toString config.ports.sonarr}/sonarr";
              prowlarrUrl = "http://127.0.0.1:${toString config.ports.prowlarr}/prowlarr";
            }
            {
              name = "Radarr";
              implementationName = "Radarr";
              apiKey._secret = config.sops.secrets."media/radarr_api_key".path;
              baseUrl = "http://127.0.0.1:${toString config.ports.radarr}/radarr";
              prowlarrUrl = "http://127.0.0.1:${toString config.ports.prowlarr}/prowlarr";
            }
            {
              name = "Lidarr";
              implementationName = "Lidarr";
              apiKey._secret = config.sops.secrets."media/lidarr_api_key".path;
              baseUrl = "http://127.0.0.1:${toString config.ports.lidarr}/lidarr";
              prowlarrUrl = "http://127.0.0.1:${toString config.ports.prowlarr}/prowlarr";
            }
            {
              name = "Sonarr Anime";
              implementationName = "Sonarr";
              apiKey._secret = config.sops.secrets."media/sonarr_api_key".path;
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
              apiKey._secret = config.sops.secrets."media/mteam_api_key".path;
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
          apiKey._secret = config.sops.secrets."media/lidarr_api_key".path;
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

      seerr = {
        enable = true;
        jellyfin.adminUsername = "i";
        jellyfin.adminPassword = {
          _secret = config.sops.secrets."password".path;
        };
        settings.users.defaultPermissions = 1024;
        apiKey._secret = config.sops.secrets."media/jellyseerr_api_key".path;
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
          apiKey._secret = config.sops.secrets."media/sonarr_api_key".path;
          rootFolders = [
            { path = "/data/media/anime"; }
          ];
        };
      };
    };

    services.traefik.proxies =
      let
        inherit (config.networking) domain;
        inherit (config.networking) fqdn;
      in
      {
        jellyfin = {
          rule = "Host(`jellyfin.${domain}`) || Host(`jellyfin.${fqdn}`)";
          target = "http://127.0.0.1:${toString config.ports.jellyfin}";
        };

        jellyseerr = {
          rule = "Host(`seerr.${domain}`) || Host(`seerr.${fqdn}`)";
          target = "http://127.0.0.1:${toString config.ports.jellyseerr}";
        };

        sonarr = {
          rule = "Host(`sonarr.${domain}`) || Host(`sonarr.${fqdn}`)";
          target = "http://127.0.0.1:${toString config.ports.sonarr}";
        };

        sonarr-anime = {
          rule = "Host(`sonarr-anime.${domain}`) || Host(`sonarr-anime.${fqdn}`)";
          target = "http://127.0.0.1:${toString config.ports.sonarr-anime}";
        };

        radarr = {
          rule = "Host(`radarr.${domain}`) || Host(`radarr.${fqdn}`)";
          target = "http://127.0.0.1:${toString config.ports.radarr}";
        };

        prowlarr = {
          rule = "Host(`prowlarr.${domain}`) || Host(`prowlarr.${fqdn}`)";
          target = "http://127.0.0.1:${toString config.ports.prowlarr}";
        };

        lidarr = {
          rule = "Host(`lidarr.${domain}`) || Host(`lidarr.${fqdn}`)";
          target = "http://127.0.0.1:${toString config.ports.lidarr}";
        };

        autobrr = {
          rule = "Host(`autobrr.${domain}`) || Host(`autobrr.${fqdn}`)";
          target = "http://127.0.0.1:${toString config.ports.autobrr}";
        };

        bazarr = {
          rule = "Host(`bazarr.${domain}`) || Host(`bazarr.${fqdn}`)";
          target = "http://127.0.0.1:${toString config.ports.bazarr}";
        };

        qbittorrent = {
          rule = "(Host(`qbit.${domain}`) || Host(`qbit.${fqdn}`))";
          target = "http://127.0.0.1:${toString config.ports.qbittorrent}";
        };

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
            AuthSubnetWhitelistEnabled = true;
            AuthSubnetWhitelist = "127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16";
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
                    CURRENT_IP=$(${pkgs.curl}/bin/curl -s https://api.ipify.org)
                    if [ -z "$CURRENT_IP" ]; then
                      echo "Failed to get public IP"
                      exit 1
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

          sonarr.serviceConfig.UMask = "0002";
          radarr.serviceConfig.UMask = "0002";
          prowlarr.serviceConfig.UMask = "0002";
          lidarr.serviceConfig.UMask = "0002";
          seerr.serviceConfig.UMask = "0002";
          sonarr-anime.serviceConfig.UMask = "0002";
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
