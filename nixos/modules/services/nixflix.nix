# Nixflix Media Stack
# Declarative media server configuration using nixflix
# https://github.com/kiriwalawren/nixflix
#
# Usage in nixos/hosts/{host}/default.nix:
#   (import nixosModules.services.nixflix { })                    # All enabled (default)
#   (import nixosModules.services.nixflix { jellyfin = false; })  # Disable Jellyfin
#
# Parameters (all default to true):
#   jellyfin, jellyseerr, sonarr, radarr, prowlarr, lidarr,
#   sabnzbd, bazarr, qbittorrent, recyclarr, flaresolverr
{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
let
  domain = "tv.dora.im";

  navHtmlDir = toString ./../../../conf/nixflix;

  subpathProxyConfig =
    {
      path,
      port ? null,
    }:
    ''
      # Cookie handling - CRITICAL for login to work
      proxy_cookie_path / /${path}/;
      proxy_cookie_flags ~ nosecure samesite=lax;
      proxy_set_header X-Forwarded-Prefix /${path};
      # Rewrite redirects
      proxy_redirect default;
      ${
        if port != null then
          ''
            proxy_redirect http://127.0.0.1:${toString port}/ /${path}/;
            proxy_redirect / /${path}/;
          ''
        else
          "proxy_redirect off;"
      }

      # Content rewriting for subpath support
      sub_filter_once off;
      sub_filter_types text/html text/css text/javascript application/javascript application/json application/xml image/svg+xml;

      # Rewrite common paths and patterns
      sub_filter '\"/assets' '\"/${path}/assets';
      sub_filter '\'/assets' '\'/${path}/assets';
      sub_filter '\"/js' '\"/${path}/js';
      sub_filter '\'/js' '\'/${path}/js';
      sub_filter '\"/css' '\"/${path}/css';
      sub_filter '\'/css' '\'/${path}/css';
      sub_filter '\"/img' '\"/${path}/img';
      sub_filter '\'/img' '\'/${path}/img';
      sub_filter '\"/fonts' '\"/${path}/fonts';
      sub_filter '\'/fonts' '\'/${path}/fonts';
      sub_filter '\"/api' '\"/${path}/api';
      sub_filter '\'/api' '\'/${path}/api';
      sub_filter '\"/app' '\"/${path}/app';
      sub_filter '\'/app' '\'/${path}/app';
      sub_filter '\"/login' '\"/${path}/login';
      sub_filter '\'/login' '\'/${path}/login';
      sub_filter '\"/user' '\"/${path}/user';
      sub_filter '\'/user' '\'/${path}/user';
      sub_filter '\"/static' '\"/${path}/static';
      sub_filter '\'/static' '\'/${path}/static';
      sub_filter '\"/manifest.json' '\"/${path}/manifest.json';
      sub_filter '\"/favicon.ico' '\"/${path}/favicon.ico';

      # CSS url() patterns
      sub_filter 'url(/assets' 'url(/${path}/assets';
      sub_filter 'url(\"/assets' 'url(\"/${path}/assets';
      sub_filter 'url(\'/assets' 'url(\'/${path}/assets';
      sub_filter 'url(/Content' 'url(/${path}/Content';
      sub_filter 'url(\"/Content' 'url(\"/${path}/Content';
      sub_filter 'url(\'/Content' 'url(\'/${path}/Content';
      sub_filter 'url(/dist' 'url(/${path}/dist';
      sub_filter 'url(/web' 'url(/${path}/web';
      sub_filter 'url(/views' 'url(/${path}/views';

      # HTML specific
      sub_filter 'src=\"/assets' 'src=\"/${path}/assets';
      sub_filter 'href=\"/assets' 'href=\"/${path}/assets';
      sub_filter 'src=\"/js' 'src=\"/${path}/js';
      sub_filter 'href=\"/css' 'href=\"/${path}/css';

      # Additional common patterns found in JS
      sub_filter '\"/Content' '\"/${path}/Content';
      sub_filter '\'/Content' '\'/${path}/Content';
      sub_filter '\"/dist' '\"/${path}/dist';
      sub_filter '\'/dist' '\'/${path}/dist';
      sub_filter '\"/web' '\"/${path}/web';
      sub_filter '\'/web' '\'/${path}/web';
      sub_filter '\"/views' '\"/${path}/views';
      sub_filter '\'/views' '\'/${path}/views';
      sub_filter '\"/signalr' '\"/${path}/signalr';
      sub_filter '\'/signalr' '\'/${path}/signalr';
      sub_filter '"/views' '"/${path}/views';
      sub_filter "'/views" "'/${path}/views";
      sub_filter '"/signalr' '"/${path}/signalr';
      sub_filter "'/signalr" "'/${path}/signalr";
      sub_filter '"/manifest.json' '"/${path}/manifest.json';
      sub_filter "'/manifest.json" "'/${path}/manifest.json";
      sub_filter '"/favicon.ico' '"/${path}/favicon.ico';
      sub_filter "'/favicon.ico" "'/${path}/favicon.ico";
      sub_filter 'url(/Content' 'url(/${path}/Content';
      sub_filter 'url("/Content' 'url("/${path}/Content';
      sub_filter "url('/Content" "url('/${path}/Content";
      sub_filter 'url(/dist' 'url(/${path}/dist';
      sub_filter 'url("/dist' 'url("/${path}/dist';
      sub_filter "url('/dist" "url('/${path}/dist";
      sub_filter 'url(/web' 'url(/${path}/web';
      sub_filter 'url("/web' 'url("/${path}/web';
      sub_filter "url('/web" "url('/${path}/web";
      sub_filter 'url(/views' 'url(/${path}/views';
      sub_filter 'url("/views' 'url("/${path}/views';
      sub_filter "url('/views" "url('/${path}/views";
      sub_filter 'url(/signalr' 'url(/${path}/signalr';
      sub_filter 'url("/signalr' 'url("/${path}/signalr';
      sub_filter "url('/signalr" "url('/${path}/signalr";
      sub_filter 'service-worker.js' '${path}/service-worker.js';
      sub_filter 'scope: "/"' 'scope: "/${path}/"';
      sub_filter "scope: '/'" "scope: '/${path}/'";
      sub_filter 'scope: "./"' 'scope: "./"'; # Preserve relative scopes
    '';
in
{
  imports = [
    inputs.nixflix.nixosModules.nixflix
  ];

  config = {
    # Core nixflix configuration (official documentation pattern)
    nixflix = {
      enable = true;
      mediaDir = "/data/media";
      stateDir = "/data/.state";
      mediaUsers = [ "i" ];

      theme = {
        enable = true;
        name = "nord";
      };

      nginx.enable = true;
      postgres.enable = false; # Use existing postgres module

      sonarr = {
        enable = true;
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
          downloadClients = lib.mkForce [
            {
              name = "SABnzbd";
              implementationName = "SABnzbd";
              apiKey = config.nixflix.sabnzbd.settings.misc.api_key;
              host = "127.0.0.1";
              port = 8090;
              urlBase = "/sabnzbd";
              tvCategory = "sonarr";
            }
            {
              name = "qBit";
              implementationName = "qBittorrent";
              apiKey = ""; # Required by nixflix schema but not used by qBit
              host = "127.0.0.1";
              port = config.ports.qbittorrent;
              username = "i";
              password = {
                _secret = config.sops.secrets."password".path;
              };
              tvCategory = "tv-sonarr";
            }
          ];
        };
      };

      radarr = {
        enable = true;
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
          downloadClients = lib.mkForce [
            {
              name = "SABnzbd";
              implementationName = "SABnzbd";
              apiKey = config.nixflix.sabnzbd.settings.misc.api_key;
              host = "127.0.0.1";
              port = 8090;
              urlBase = "/sabnzbd";
              movieCategory = "radarr";
            }
            {
              name = "qBit";
              implementationName = "qBittorrent";
              apiKey = "";
              host = "127.0.0.1";
              port = config.ports.qbittorrent;
              username = "i";
              password = {
                _secret = config.sops.secrets."password".path;
              };
              movieCategory = "movies-radarr";
            }
          ];
        };
      };

      prowlarr = {
        enable = true;
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
            }
            {
              name = "Radarr";
              implementationName = "Radarr";
              apiKey = {
                _secret = config.sops.secrets."media/radarr_api_key".path;
              };
            }
            {
              name = "Lidarr";
              implementationName = "Lidarr";
              apiKey = {
                _secret = config.sops.secrets."media/lidarr_api_key".path;
              };
            }
          ];
          # PT Indexers
          indexers = [
            {
              id = 0;
              name = "M-Team - TP";
              enable = false;
              freeleechOnly = true;
              baseUrl = "https://kp.m-team.cc/";
              apiKey = {
                _secret = config.sops.secrets."media/mteam_api_key".path;
              };
            }
            {
              # id = 1;
              name = "PTTime";
              enable = true;
              baseUrl = "https://www.pttime.org/";
              # freeleechOnly = true;
              # searchFreeleechOnly = true;
              username = {
                _secret = config.sops.secrets."media/pttime_username".path;
              };
              password = {
                _secret = config.sops.secrets."password".path;
              };
            }
          ];
          downloadClients = [
            {
              name = "qBittorrent";
              implementationName = "qBittorrent";
              apiKey = "";
              host = "127.0.0.1";
              port = config.ports.qbittorrent;
              username = "i";
              password = {
                _secret = config.sops.secrets."password".path;
              };
            }
          ];
        };
      };

      lidarr = {
        enable = true;
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
          downloadClients = lib.mkForce [
            {
              name = "SABnzbd";
              implementationName = "SABnzbd";
              apiKey = config.nixflix.sabnzbd.settings.misc.api_key;
              host = "127.0.0.1";
              port = 8090;
              urlBase = "/sabnzbd";
              musicCategory = "lidarr";
            }
            {
              name = "qBit";
              implementationName = "qBittorrent";
              apiKey = "";
              host = "127.0.0.1";
              port = config.ports.qbittorrent;
              username = "i";
              password = {
                _secret = config.sops.secrets."password".path;
              };
              musicCategory = "music-lidarr";
            }
          ];
        };
      };

      sabnzbd = {
        enable = true;
        settings = {
          misc = {
            port = config.ports.sabnzbd;
            api_key = {
              _secret = config.sops.secrets."media/sabnzbd_api_key".path;
            };
            nzb_key = {
              _secret = config.sops.secrets."media/sabnzbd_nzb_key".path;
            };
            host_whitelist = [
              domain
              "localhost"
              "127.0.0.1"
              config.networking.fqdn
            ];
          };
        };
      };

      recyclarr = {
        enable = true;
        cleanupUnmanagedProfiles = true;
      };

      jellyfin = {
        enable = true;
        users = {
          i = {
            mutable = false;
            policy.isAdministrator = true;
            password = {
              _secret = config.sops.secrets."password".path;
            };
          };
        };
      };

      jellyseerr = {
        enable = true;
        apiKey = {
          _secret = config.sops.secrets."media/jellyseerr_api_key".path;
        };
      };

      sonarr-anime = {
        enable = true;
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
        };
      };
    };

    # Consolidated Services Configuration
    services = {
      # Bazarr - Subtitle Management (native service)
      bazarr = {
        enable = true;
        group = "media";
        listenPort = config.ports.bazarr;
      };

      # FlareSolverr - Cloudflare bypass
      flaresolverr = {
        enable = true;
        port = config.ports.flaresolverr;
      };

      # qBittorrent - Torrent client with VueTorrent UI
      qbittorrent = {
        enable = true;
        group = "media";
        webuiPort = config.ports.qbittorrent;
        serverConfig.Preferences = {
          WebUI = {
            AlternativeUIEnabled = true;
            RootFolder = "${pkgs.vuetorrent}/share/vuetorrent";
            Username = "i";
            CSRFProtection = false;
            HostHeaderValidation = false;
            ServerDomains = "*";
            SecureCookie = false;
            ClickjackingProtection = false;
            LocalHostAuth = false;
            # AuthSubnetWhitelistEnabled = true;
            # AuthSubnetWhitelist = "127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16";
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
          };
          BitTorrent = {
            "Session\\DefaultSavePath" = "/data/downloads/torrents";
            "Session\\TempPath" = "/data/downloads/torrents/.incomplete";
            "Session\\TempPathEnabled" = true;
            "Session\\BTProtocol" = "Both";
            "Session\\MaxConnections" = 4000;
            "Session\\MaxConnectionsPerTorrent" = 500;
            "Session\\MaxUploads" = 200;
            "Session\\MaxUploadsPerTorrent" = 50;
            "Session\\EnableSuperSeeding" = true;
            "Session\\ChokingAlgorithm" = "FastestUpload";
            "Session\\SeedChokingAlgorithm" = "AntiLeech";
            "Session\\UploadSlotsBehavior" = "UploadRateBased";
            "Session\\QueueingSystemEnabled" = true;
            "Session\\MaxActiveDownloads" = 20;
            "Session\\MaxActiveUploads" = 100;
            "Session\\MaxActiveTorrents" = 120;
            "Session\\AnnounceToAllTrackers" = true;
            "Session\\AnnounceToAllTiers" = true;
            "Session\\TrackerExchangeEnabled" = true;
            "Session\\Encryption" = 1;
            "Session\\AnonymousMode" = true;
          };
        };
      };

      autobrr = {
        enable = true;
        secretFile = config.sops.secrets."media/autobrr_session_token".path;
        settings = {
          host = "127.0.0.1";
          port = config.ports.autobrr;
          baseUrl = "/autobrr/";
          metricsBasicAuthUsers = "i:$2y$05$yaH6RqWhDQGPvLI7vyVdY.EsH8LBrNaAS30HJwXiCHziIFf7csVbi";
        };
      };

      nginx = {
        enable = lib.mkForce true;
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
            proxy_set_header Origin "";
            proxy_set_header Referer "";
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $http_connection;
          '';
          locations = {
            "/" = {
              extraConfig = ''
                root ${navHtmlDir};
                try_files /nav.html =404;
                default_type text/html;
              '';
            };
            "/bazarr" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.bazarr}";
              extraConfig = subpathProxyConfig {
                path = "bazarr";
                port = config.ports.bazarr;
              };
            };
            "/autobrr/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.autobrr}";
              proxyWebsockets = true;
              extraConfig = ''
                # rewrite ^/autobrr/(.*) /$1 break;
              '';
            };
            "/autobrr" = {
              return = "301 /autobrr/";
            };
            "/qbit/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.qbittorrent}/";
              extraConfig = subpathProxyConfig {
                path = "qbit";
                port = config.ports.qbittorrent;
              };
            };
            "/qbit" = {
              return = "301 /qbit/";
            };

            "/vertex/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.vertex}";
              proxyWebsockets = true;
              extraConfig =
                subpathProxyConfig {
                  path = "vertex";
                  port = config.ports.vertex;
                }
                + ''
                  proxy_redirect / /vertex/;
                '';
            };
            "/vertex" = {
              return = "301 /vertex/";
            };

            "/iyuu/" = {
              proxyPass = "http://127.0.0.1:8777/";
              proxyWebsockets = true;
              extraConfig = subpathProxyConfig {
                path = "iyuu";
                port = 8777;
              };
            };
            "/iyuu" = {
              return = "301 /iyuu/";
            };

            "/whoami/" = {
              proxyPass = "http://127.0.0.1:8082/";
              extraConfig = subpathProxyConfig {
                path = "whoami";
                port = 8082;
              };
            };
            "/whoami" = {
              return = "301 /whoami/";
            };

            # Delegated to nixflix nginx: sonarr, radarr, lidarr, sabnzbd, jellyfin, jellyseerr, prowlarr
          };
        };
      };

      traefik.dynamicConfigOptions.http = {
        routers = {
          nixflix-nav = {
            rule = "Host(`${domain}`) && Path(`/`)";
            entryPoints = [ "https" ];
            service = "nixflix-nginx";
          };
          nixflix-apps = {
            rule = "(Host(`${domain}`) || Host(`${config.networking.fqdn}`)) && (PathPrefix(`/bazarr`) || PathPrefix(`/sonarr`) || PathPrefix(`/sonarr-anime`) || PathPrefix(`/radarr`) || PathPrefix(`/prowlarr`) || PathPrefix(`/lidarr`) || PathPrefix(`/sabnzbd`) || PathPrefix(`/jellyfin`) || PathPrefix(`/jellyseerr`) || PathPrefix(`/autobrr`) || PathPrefix(`/iyuu`) || PathPrefix(`/qbit`) || PathPrefix(`/vertex`) || PathPrefix(`/whoami`))";
            entryPoints = [ "https" ];
            service = "nixflix-nginx";
          };
        };
        services = {
          nixflix-nginx.loadBalancer.servers = [
            { url = "http://127.0.0.1:${toString config.ports.nginx}"; }
          ];
        };
      };
    };

    # Consolidated Systemd Configuration
    systemd = {
      tmpfiles.rules = [
        "d /data 0755 root media -"
        "d /data/media 0755 root media -"
        "d /data/downloads 0755 root media -"
        "d /data/downloads/usenet 0755 sabnzbd media -"
        "d /data/downloads/usenet/incomplete 0755 sabnzbd media -"
        "d /data/downloads/usenet/complete 0755 sabnzbd media -"
        "d /data/.state 0755 root media -"
        "d /data/downloads/torrents 0755 qbittorrent media -"
        "d /data/downloads/torrents/.incomplete 0755 qbittorrent media -"
        "d /data/downloads/torrents/tv-sonarr 0755 qbittorrent media -"
        "d /data/downloads/torrents/movies-radarr 0755 qbittorrent media -"
        "d /data/downloads/torrents/music-lidarr 0755 qbittorrent media -"
        "d /data/downloads/torrents/prowlarr 0755 qbittorrent media -"
        "d /data/torrents 0755 qbittorrent media -"
        "d /data/torrents/downloading 0755 qbittorrent media -"
        "d /data/torrents/completed 0755 qbittorrent media -"
        "d /data/.state/jellyfin 0755 jellyfin media -"
        "d /data/.state/jellyseerr 0755 jellyseerr media -"
        "d /data/.state/sonarr 0755 sonarr media -"
        "d /data/.state/sonarr-anime 0755 sonarr-anime media -"
        "d /data/.state/radarr 0755 radarr media -"
        "d /data/.state/prowlarr 0755 prowlarr media -"
        "d /data/.state/lidarr 0755 lidarr media -"
        "d /data/.state/sabnzbd 0755 sabnzbd media -"
        "d /data/.state/recyclarr 0755 recyclarr media -"
        "d /data/.state/autobrr 0755 autobrr media -"
        "d /data/.state/moviepilot 0755 root media -"
        "d /data/.state/moviepilot/core 0755 root media -"
        "d /data/.state/vertex 0755 root media -"
        "d /data/.state/iyuu 0755 root media -"
        "d /srv/moviepilot-plugins 0755 root media -"
        "d /var/lib/bazarr 0755 bazarr media -"
        "d /var/lib/qBittorrent 0755 qbittorrent media -"
        "d /var/lib/iyuu 0755 iyuu media -"
        "d /var/lib/autobrr 0755 autobrr media -"
      ];

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
              value.serviceConfig.Restart = lib.mkForce "on-failure";
            })
            [
              "jellyfin"
              "jellyseerr"
              "sonarr"
              "radarr"
              "prowlarr"
              "lidarr"
              "sabnzbd"
              "bazarr"
              "qbittorrent"
              "flaresolverr"
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
              "jellyfin-setup-wizard"
              "jellyfin-system-config"
              "jellyfin-encoding-config"
              "jellyfin-branding-config"
              "jellyfin-libraries"
              "jellyseerr-setup"
              "jellyseerr-sonarr"
              "jellyseerr-radarr"
              "jellyseerr-libraries"
            ]
        ))
        // {
          sabnzbd-categories.enable = lib.mkForce false;

          # Fix qBittorrent service crash settings
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
            # Sandboxing fixes for libtorrent ABRT
            ProtectHome = lib.mkForce false;
            ProtectSystem = lib.mkForce false;
            PrivateTmp = lib.mkForce false;
            NoNewPrivileges = lib.mkForce false;
            SystemCallFilter = lib.mkForce [ ];
            ProtectProc = lib.mkForce "default";
            ProcSubset = lib.mkForce "all";
          };

          # Fix autobrr service - disable DynamicUser to use our pre-created directory
          autobrr.serviceConfig = {
            DynamicUser = lib.mkForce false;
            User = lib.mkForce "autobrr";
            Group = lib.mkForce "media";
            StateDirectory = lib.mkForce "";
            WorkingDirectory = "/var/lib/autobrr";
          };

          media-stack-init = {
            description = "Automated configuration for media stack connections";
            after = [
              "sonarr.service"
              "radarr.service"
              "prowlarr.service"
              "bazarr.service"
              "qbittorrent.service"
              "postgresql-ready.target"
            ];
            wants = [
              "sonarr.service"
              "radarr.service"
              "prowlarr.service"
              "bazarr.service"
              "qbittorrent.service"
            ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              Restart = "on-failure";
              RestartSec = "30s";
            };
            path = [ pkgs.curl ];
            script = ''
              # Wait for all services to be healthy
              for service in sonarr:${toString config.ports.sonarr}/sonarr \
                             radarr:${toString config.ports.radarr}/radarr \
                             lidarr:${toString config.ports.lidarr}/lidarr \
                             prowlarr:${toString config.ports.prowlarr}/prowlarr \
                             bazarr:${toString config.ports.bazarr}/ \
                             autobrr:${toString config.ports.autobrr}/autobrr \
                             vertex:${toString config.ports.vertex}/vertex \
                             qbittorrent:${toString config.ports.qbittorrent}/ \
                             sonarr-anime:8990/sonarr-anime; do
                host=''${service%%:*}
                path_port=''${service#*:}
                until curl -s "http://127.0.0.1:$path_port" > /dev/null; do
                  echo "Waiting for $host on $path_port..."
                  sleep 5
                done
              done

              # Run unified setup script
              # Run unified setup script
              ${pkgs.python3.withPackages (ps: [ ps.requests ])}/bin/python3 ${navHtmlDir}/setup.py \
                --bazarr-url "http://127.0.0.1:${toString config.ports.bazarr}/api" \
                --autobrr-url "http://127.0.0.1:${toString config.ports.autobrr}/autobrr" \
                --prowlarr-url "http://127.0.0.1:${toString config.ports.prowlarr}/prowlarr" \
                --sonarr-url "http://127.0.0.1:${toString config.ports.sonarr}/sonarr" \
                --radarr-url "http://127.0.0.1:${toString config.ports.radarr}/radarr" \
                --sonarr-key-file "${config.sops.secrets."media/sonarr_api_key".path}" \
                --radarr-key-file "${config.sops.secrets."media/radarr_api_key".path}" \
                --prowlarr-key-file "${config.sops.secrets."media/prowlarr_api_key".path}" \
                --autobrr-key-file "${config.sops.secrets."media/autobrr_session_token".path}" \
                --password-file "${config.sops.secrets."password".path}" \
                --qbit-port "${toString config.ports.qbittorrent}" \
                --sonarr-port "${toString config.ports.sonarr}" \
                --radarr-port "${toString config.ports.radarr}" \
                --mteam-rss-file "${config.sops.secrets."media/mteam_rss_url".path}" \
                --pttime-rss-file "${config.sops.secrets."media/pttime_rss_url".path}"
            '';
          };

          qbittorrent-password = {
            description = "Set qBittorrent WebUI password";
            before = [ "qbittorrent.service" ];
            requiredBy = [ "qbittorrent.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ProtectSystem = "no";
              ProtectHome = "no";
              ReadWritePaths = [ "/var/lib/qBittorrent" ];
              User = "root";
            };
            path = [
              pkgs.python3
              pkgs.coreutils
              pkgs.gnused
            ];
            script = ''
                                     CONFIG_FILE="/var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf"
                                     PASSWORD_FILE="${config.sops.secrets."password".path}"
                                     export PASSWORD=$(cat "$PASSWORD_FILE" | tr -d '\n')
                                     HASH=$(python3 << 'PYTHON_EOF'
              import hashlib
              import base64
              import secrets
              import os
              password = os.environ.get('PASSWORD', 'changeme')
              salt = secrets.token_bytes(16)
              iterations = 100000
              dk = hashlib.pbkdf2_hmac('sha512', password.encode(), salt, iterations, dklen=64)
              result = base64.b64encode(salt + dk).decode()
              print(f'@ByteArray({result})')
              PYTHON_EOF
                                     )
                                     mkdir -p "$(dirname "$CONFIG_FILE")"

                                     # If config is a symlink (from Nix store), replace with actual file
                                     if [ -L "$CONFIG_FILE" ]; then
                                       cp --remove-destination "$(readlink -f "$CONFIG_FILE")" "$CONFIG_FILE"
                                       chmod 600 "$CONFIG_FILE"
                                     elif [ ! -f "$CONFIG_FILE" ]; then
                                       touch "$CONFIG_FILE"
                                       chmod 600 "$CONFIG_FILE"
                                     fi

                                     chown -R qbittorrent:media /var/lib/qBittorrent
                                     grep -q "\[Preferences\]" "$CONFIG_FILE" || echo "[Preferences]" >> "$CONFIG_FILE"
                                     sed -i '/WebUI\\Password_PBKDF2/d' "$CONFIG_FILE"
                                     sed -i "/\[Preferences\]/a WebUI\\Password_PBKDF2=$HASH" "$CONFIG_FILE"
                                     echo "qBittorrent password configured"
            '';
          };

          jellyfin.serviceConfig = {
            PrivateUsers = lib.mkForce false;
          };
        };
    };

    # Other system settings (Boot, Networking, Users, SOPs, Containers)
    boot.kernel.sysctl = {
      "net.ipv4.tcp_max_orphans" = lib.mkDefault 65535;
      "net.ipv4.tcp_sack" = lib.mkDefault 1;
      "net.ipv4.tcp_timestamps" = lib.mkDefault 1;
      "net.core.optmem_max" = lib.mkDefault 65535;
      "fs.nr_open" = lib.mkDefault 2097152;
      "net.ipv4.tcp_mem" = lib.mkDefault "786432 1048576 134217728";
      "net.ipv4.udp_mem" = lib.mkDefault "786432 1048576 134217728";
    };

    networking.hosts."127.0.0.1" = [
      "sonarr"
      "radarr"
      "prowlarr"
      "lidarr"
      "sabnzbd"
      "bazarr"
      "qbittorrent"
    ];

    environment.global-persistence.directories = [
      "/data"
      "/var/lib/bazarr"
      "/var/lib/qbittorrent"
      "/data/.state/autobrr"
    ];

    users.users.iyuu = {
      isSystemUser = true;
      group = "media";
      home = "/var/lib/iyuu";
      createHome = true;
    };

    users.users.autobrr = {
      isSystemUser = true;
      group = "media";
      home = "/var/lib/autobrr";
      createHome = true;
    };

    sops.templates."iyuu-env" = {
      content = ''
        SERVER_LISTEN_PORT=${toString config.ports.iyuu}
        IYUU_TOKEN=${config.sops.placeholder."media/iyuu_token"}
        CONFIG_NOT_MYSQL=1
        # IYUU_APPID=
      '';
      owner = "iyuu";
      group = "media";
    };

    virtualisation.oci-containers = {
      backend = "podman";
      containers.vertex = {
        image = "docker://lswl/vertex:latest";
        volumes = [
          "/data/.state/vertex:/vertex/data"
          "/data/downloads/torrents:/data/downloads/torrents"
        ];
        environment = {
          TZ = "Asia/Shanghai";
          PORT = toString config.ports.vertex;
          USERNAME = "i";
        };
        environmentFiles = [ config.sops.secrets.password.path ]; # This file contains PASSWORD=...
        extraOptions = [ "--network=host" ];
      };

      containers.iyuu = {
        image = "docker://iyuucn/iyuuplus:latest";
        volumes = [
          "/data/.state/iyuu:/iyuu"
          "/data/downloads/torrents:/data/downloads/torrents"
        ];
        environment = {
          TZ = "Asia/Shanghai";
          # For initial login if supported by image, or consistency
          IYUU_ADMIN_USER = "i";
        };
        environmentFiles = [
          config.sops.templates."iyuu-env".path
          config.sops.secrets.password.path # Adds PASSWORD=...
        ];
        extraOptions = [ "--network=host" ];
      };

      containers.whoami = {
        image = "docker.io/traefik/whoami";
        cmd = [
          "--port"
          "8082"
        ];
        extraOptions = [ "--network=host" ];
      };
    };

    sops.secrets =
      let
        mkSecret = mode: name: { inherit mode; } // { inherit name; };
        mkArr =
          mode: names:
          builtins.listToAttrs (
            map (n: {
              name = n;
              value = mkSecret mode n;
            }) names
          );
      in
      mkArr "0444" [ "password" ]
      // mkArr "0400" [
        "media/sonarr_api_key"
        "media/radarr_api_key"
        "media/prowlarr_api_key"
        "media/jellyfin_api_key"
        "media/jellyseerr_api_key"
        "media/lidarr_api_key"
        "media/sabnzbd_api_key"
        "media/sabnzbd_nzb_key"
        "media/mteam_api_key"
        "media/pttime_api_key"
        "media/iyuu_token"
        "media/autobrr_session_token"
        "media/pttime_username"
        "media/mteam_rss_url"
        "media/pttime_rss_url"
        "media/moviepilot_api_key"
        "media/jellyfin_api_key" # Explicitly included as it was missing from the list but used
      ];
  };
}
