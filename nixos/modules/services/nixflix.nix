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
      # ============================================================
      # ULTIMATE SUBPATH PROXY CONFIG - Maximum Compatibility Mode
      # ============================================================

      # --- CRITICAL: Disable compression to allow sub_filter to work ---
      proxy_set_header Accept-Encoding "";

      # --- Cookie handling - CRITICAL for login/sessions ---
      proxy_cookie_path / /${path}/;
      proxy_cookie_path ~^/(.+)$ /${path}/$1;
      proxy_cookie_flags ~ nosecure samesite=lax;
      # proxy_cookie_domain ~\.?(.+)$ $host;

      # --- Essential headers for subpath awareness ---
      proxy_set_header X-Forwarded-Prefix /${path};
      proxy_set_header X-Base-URL /${path};
      proxy_set_header X-Script-Name /${path};
      proxy_set_header X-Ingress-Path /${path};

      # --- Redirect rewriting ---
      proxy_redirect default;
      proxy_redirect ~^/(.*)$ /${path}/$1;
      ${
        if port != null then
          ''
            proxy_redirect http://127.0.0.1:${toString port}/ /${path}/;
            proxy_redirect http://localhost:${toString port}/ /${path}/;
            proxy_redirect http://127.0.0.1:${toString port} /${path};
            proxy_redirect / /${path}/;
          ''
        else
          ''
            proxy_redirect off;
          ''
      }


      # --- WebSocket settings removed (handled by proxyWebsockets = true in location) ---
       # proxy_http_version 1.1;
       # proxy_read_timeout 86400s;
       # proxy_send_timeout 86400s;

      # --- Buffering settings for sub_filter ---
      proxy_buffering on;
      proxy_buffer_size 128k;
      proxy_buffers 4 256k;
      proxy_busy_buffers_size 256k;

      # ============================================================
      # CONTENT REWRITING - User requested broad but safe rules
      # ============================================================
      sub_filter_once off;
      # text/html is default, adding others as requested
      sub_filter_types
        text/css
        text/javascript
        application/javascript
        application/x-javascript
        application/json
        application/xml
        image/svg+xml;

      # --- Surgical Contextual Rewriting (HTML/CSS/JS safe) ---
      sub_filter ' href="/' ' href="/${path}/';
      sub_filter ' src="/' ' src="/${path}/';
      sub_filter ' action="/' ' action="/${path}/';
      sub_filter ' url("/' ' url("/${path}/';
      sub_filter " url('/" " url('/${path}/";
      sub_filter ' fetch("/' ' fetch("/${path}/';
      sub_filter ' axios.get("/' ' axios.get("/${path}/';
      sub_filter ' serviceWorker.register("/' ' serviceWorker.register("/${path}/';
      sub_filter ' registerServiceWorker("/' ' registerServiceWorker("/${path}/';
      sub_filter ' window.location="/' ' window.location="/${path}/';
      sub_filter ' location.href="/' ' location.href="/${path}/';

      # --- JSON/JS string paths (targeting common patterns) ---
      sub_filter '": "/' '": "/${path}/';
      sub_filter "': '/" "': '/${path}/";
      sub_filter 'path: "/' 'path: "/${path}/';
      sub_filter "path: '/" "path: '/${path}/";

      # --- Absolute root paths with single quotes ---
      # sub_filter "='/" "='/${path}/";
      # sub_filter "= '/" "= '/${path}/";

      # --- JSON/JS string paths ---
      sub_filter '": /' '": /${path}/';
      sub_filter '": "/' '": "/${path}/';
      sub_filter "': /" "': /${path}/";
      sub_filter "': '/" "': '/${path}/";

      # --- Common HTML attributes with absolute paths ---
      sub_filter ' href="/' ' href="/${path}/';
      sub_filter " href='/" " href='/${path}/";
      sub_filter ' src="/' ' src="/${path}/';
      sub_filter " src='/" " src='/${path}/";
      sub_filter ' action="/' ' action="/${path}/';
      sub_filter " action='/" " action='/${path}/";
      sub_filter ' data-url="/' ' data-url="/${path}/';
      sub_filter " data-url='/" " data-url='/${path}/";
      sub_filter ' data-src="/' ' data-src="/${path}/';
      sub_filter " data-src='/" " data-src='/${path}/";
      sub_filter ' data-href="/' ' data-href="/${path}/';
      sub_filter " data-href='/" " data-href='/${path}/";
      sub_filter ' poster="/' ' poster="/${path}/';
      sub_filter " poster='/" " poster='/${path}/";
      sub_filter ' content="/' ' content="/${path}/';
      sub_filter " content='/" " content='/${path}/";

      # --- CSS url() patterns ---
      sub_filter 'url(/' 'url(/${path}/';
      sub_filter 'url("/' 'url("/${path}/';
      sub_filter "url('/" "url('/${path}/";
      sub_filter 'url( /' 'url( /${path}/';
      sub_filter 'url( "/' 'url( "/${path}/';
      sub_filter "url( '/" "url( '/${path}/";

      # --- @import CSS patterns ---
      sub_filter '@import "/' '@import "/${path}/';
      sub_filter "@import '/" "@import '/${path}/";
      sub_filter '@import url("/' '@import url("/${path}/';
      sub_filter "@import url('/" "@import url('/${path}/";

      # --- JavaScript fetch/XHR patterns ---
      sub_filter 'fetch("/' 'fetch("/${path}/';
      sub_filter "fetch('/" "fetch('/${path}/";
      sub_filter 'fetch(`/' 'fetch(`/${path}/';
      sub_filter 'axios.get("/' 'axios.get("/${path}/';
      sub_filter "axios.get('/" "axios.get('/${path}/";
      sub_filter 'axios.post("/' 'axios.post("/${path}/';
      sub_filter "axios.post('/" "axios.post('/${path}/";
      sub_filter 'axios.put("/' 'axios.put("/${path}/';
      sub_filter "axios.put('/" "axios.put('/${path}/";
      sub_filter 'axios.delete("/' 'axios.delete("/${path}/';
      sub_filter "axios.delete('/" "axios.delete('/${path}/";
      # jQuery patterns removed due to nginx variable conflict with $
      sub_filter 'XMLHttpRequest.open("GET","/' 'XMLHttpRequest.open("GET","/${path}/';
      sub_filter 'XMLHttpRequest.open("POST","/' 'XMLHttpRequest.open("POST","/${path}/';

      # --- Vue/React/Angular router patterns ---
      sub_filter 'to="/' 'to="/${path}/';
      sub_filter "to='/" "to='/${path}/";
      sub_filter ':to="/' ':to="/${path}/';
      sub_filter ":to='/" ":to='/${path}/";
      sub_filter 'router.push("/' 'router.push("/${path}/';
      sub_filter "router.push('/" "router.push('/${path}/";
      sub_filter 'router.replace("/' 'router.replace("/${path}/';
      sub_filter "router.replace('/" "router.replace('/${path}/";
      sub_filter 'navigate("/' 'navigate("/${path}/';
      sub_filter "navigate('/" "navigate('/${path}/";
      sub_filter 'redirect:"/' 'redirect:"/${path}/';
      sub_filter "redirect:'/" "redirect:'/${path}/";
      sub_filter 'path:"/' 'path:"/${path}/';
      sub_filter "path:'/" "path:'/${path}/";
      sub_filter 'location.href="/' 'location.href="/${path}/';
      sub_filter "location.href='/" "location.href='/${path}/";
      sub_filter 'location.pathname="/' 'location.pathname="/${path}/';
      sub_filter "location.pathname='/" "location.pathname='/${path}/";
      sub_filter 'window.location="/' 'window.location="/${path}/';
      sub_filter "window.location='/" "window.location='/${path}/";
      sub_filter 'history.pushState' 'history.pushState';
      sub_filter 'history.replaceState' 'history.replaceState';

      # --- Service Worker and PWA ---
      sub_filter 'serviceWorker.register("/' 'serviceWorker.register("/${path}/';
      sub_filter "serviceWorker.register('/" "serviceWorker.register('/${path}/";
      sub_filter 'navigator.serviceWorker.register("/' 'navigator.serviceWorker.register("/${path}/';
      sub_filter "navigator.serviceWorker.register('/" "navigator.serviceWorker.register('/${path}/";
      sub_filter 'scope:"/' 'scope:"/${path}/';
      sub_filter "scope:'/" "scope:'/${path}/";
      sub_filter 'scope: "/' 'scope: "/${path}/';
      sub_filter "scope: '/" "scope: '/${path}/";
      sub_filter '"start_url":"/' '"start_url":"/${path}/';
      sub_filter '"scope":"/' '"scope":"/${path}/';
      sub_filter '"start_url": "/' '"start_url": "/${path}/';
      sub_filter '"scope": "/' '"scope": "/${path}/';

      # --- WebSocket paths ---
      sub_filter 'new WebSocket("ws://' 'new WebSocket("ws://';
      sub_filter 'new WebSocket("wss://' 'new WebSocket("wss://';
      sub_filter "'ws://' + location.host + \"/\"" "'ws://' + location.host + \"/${path}/\"";
      sub_filter "'wss://' + location.host + \"/\"" "'wss://' + location.host + \"/${path}/\"";

      # --- SignalR (ASP.NET real-time) ---
      sub_filter '"/signalr' '"/${path}/signalr';
      sub_filter "'/signalr" "'/${path}/signalr";
      sub_filter '"/hubs' '"/${path}/hubs';
      sub_filter "'/hubs" "'/${path}/hubs";

      # --- Common static asset directories ---
      sub_filter '"/assets' '"/${path}/assets';
      sub_filter "'/assets" "'/${path}/assets";
      sub_filter '"/static' '"/${path}/static';
      sub_filter "'/static" "'/${path}/static";
      sub_filter '"/js' '"/${path}/js';
      sub_filter "'/js" "'/${path}/js";
      sub_filter '"/css' '"/${path}/css';
      sub_filter "'/css" "'/${path}/css";
      sub_filter '"/img' '"/${path}/img';
      sub_filter "'/img" "'/${path}/img";
      sub_filter '"/images' '"/${path}/images';
      sub_filter "'/images" "'/${path}/images";
      sub_filter '"/fonts' '"/${path}/fonts';
      sub_filter "'/fonts" "'/${path}/fonts";
      sub_filter '"/media' '"/${path}/media';
      sub_filter "'/media" "'/${path}/media";
      sub_filter '"/dist' '"/${path}/dist';
      sub_filter "'/dist" "'/${path}/dist";
      sub_filter '"/build' '"/${path}/build';
      sub_filter "'/build" "'/${path}/build";
      sub_filter '"/public' '"/${path}/public';
      sub_filter "'/public" "'/${path}/public";
      sub_filter '"/vendor' '"/${path}/vendor';
      sub_filter "'/vendor" "'/${path}/vendor";
      sub_filter '"/lib' '"/${path}/lib';
      sub_filter "'/lib" "'/${path}/lib";
      sub_filter '"/node_modules' '"/${path}/node_modules';
      sub_filter "'/node_modules" "'/${path}/node_modules";
      sub_filter '"/Content' '"/${path}/Content';
      sub_filter "'/Content" "'/${path}/Content";
      sub_filter '"/Scripts' '"/${path}/Scripts';
      sub_filter "'/Scripts" "'/${path}/Scripts";
      sub_filter '"/bundles' '"/${path}/bundles';
      sub_filter "'/bundles" "'/${path}/bundles";

      # --- Common app routes ---
      sub_filter '"/api' '"/${path}/api';
      sub_filter "'/api" "'/${path}/api";
      sub_filter '"/v1' '"/${path}/v1';
      sub_filter "'/v1" "'/${path}/v1";
      sub_filter '"/v2' '"/${path}/v2';
      sub_filter "'/v2" "'/${path}/v2";
      sub_filter '"/auth' '"/${path}/auth';
      sub_filter "'/auth" "'/${path}/auth";
      sub_filter '"/login' '"/${path}/login';
      sub_filter "'/login" "'/${path}/login";
      sub_filter '"/logout' '"/${path}/logout';
      sub_filter "'/logout" "'/${path}/logout";
      sub_filter '"/user' '"/${path}/user';
      sub_filter "'/user" "'/${path}/user";
      sub_filter '"/users' '"/${path}/users';
      sub_filter "'/users" "'/${path}/users";
      sub_filter '"/account' '"/${path}/account';
      sub_filter "'/account" "'/${path}/account";
      sub_filter '"/profile' '"/${path}/profile';
      sub_filter "'/profile" "'/${path}/profile";
      sub_filter '"/settings' '"/${path}/settings';
      sub_filter "'/settings" "'/${path}/settings";
      sub_filter '"/admin' '"/${path}/admin';
      sub_filter "'/admin" "'/${path}/admin";
      sub_filter '"/dashboard' '"/${path}/dashboard';
      sub_filter "'/dashboard" "'/${path}/dashboard";
      sub_filter '"/app' '"/${path}/app';
      sub_filter "'/app" "'/${path}/app";
      sub_filter '"/home' '"/${path}/home';
      sub_filter "'/home" "'/${path}/home";
      sub_filter '"/web' '"/${path}/web';
      sub_filter "'/web" "'/${path}/web";
      sub_filter '"/views' '"/${path}/views';
      sub_filter "'/views" "'/${path}/views";
      sub_filter '"/socket' '"/${path}/socket';
      sub_filter "'/socket" "'/${path}/socket";
      sub_filter '"/ws' '"/${path}/ws';
      sub_filter "'/ws" "'/${path}/ws";
      sub_filter '"/stream' '"/${path}/stream';
      sub_filter "'/stream" "'/${path}/stream";
      sub_filter '"/config' '"/${path}/config';
      sub_filter "'/config" "'/${path}/config";
      sub_filter '"/health' '"/${path}/health';
      sub_filter "'/health" "'/${path}/health";
      sub_filter '"/status' '"/${path}/status';
      sub_filter "'/status" "'/${path}/status";

      # --- Meta tags and common files ---
      sub_filter '"/manifest.json' '"/${path}/manifest.json';
      sub_filter "'/manifest.json" "'/${path}/manifest.json";
      sub_filter '"/favicon.ico' '"/${path}/favicon.ico';
      sub_filter "'/favicon.ico" "'/${path}/favicon.ico";
      sub_filter '"/favicon.png' '"/${path}/favicon.png';
      sub_filter '"/apple-touch-icon' '"/${path}/apple-touch-icon';
      sub_filter '"/robots.txt' '"/${path}/robots.txt';
      sub_filter '"/sitemap.xml' '"/${path}/sitemap.xml';
      sub_filter '"/sw.js' '"/${path}/sw.js';
      sub_filter '"/service-worker.js' '"/${path}/service-worker.js';
      sub_filter '"/workbox' '"/${path}/workbox';

      # --- Media stack specific paths (Sonarr/Radarr/Jellyfin/etc) ---
      sub_filter '"/system' '"/${path}/system';
      sub_filter "'/system" "'/${path}/system";
      sub_filter '"/library' '"/${path}/library';
      sub_filter "'/library" "'/${path}/library";
      sub_filter '"/queue' '"/${path}/queue';
      sub_filter "'/queue" "'/${path}/queue";
      sub_filter '"/calendar' '"/${path}/calendar';
      sub_filter "'/calendar" "'/${path}/calendar";
      sub_filter '"/wanted' '"/${path}/wanted';
      sub_filter "'/wanted" "'/${path}/wanted";
      sub_filter '"/activity' '"/${path}/activity';
      sub_filter "'/activity" "'/${path}/activity";
      sub_filter '"/series' '"/${path}/series';
      sub_filter "'/series" "'/${path}/series";
      sub_filter '"/movie' '"/${path}/movie';
      sub_filter "'/movie" "'/${path}/movie";
      sub_filter '"/artist' '"/${path}/artist';
      sub_filter "'/artist" "'/${path}/artist";
      sub_filter '"/album' '"/${path}/album';
      sub_filter "'/album" "'/${path}/album";
      sub_filter '"/indexer' '"/${path}/indexer';
      sub_filter "'/indexer" "'/${path}/indexer";
      sub_filter '"/download' '"/${path}/download';
      sub_filter "'/download" "'/${path}/download";
      sub_filter '"/Items' '"/${path}/Items';
      sub_filter "'/Items" "'/${path}/Items";

      # --- Template literal backticks (ES6) ---
      sub_filter '`/' '`/${path}/';

      # --- Prevent double-prefixing (safety net) ---
      sub_filter '/${path}/${path}/' '/${path}/';
      sub_filter '"/${path}/${path}/' '"/${path}/';
      sub_filter "'/${path}/${path}/" "'/${path}/";

      # --- Fix double-rewriting in API paths (VueTorrent/qBittorrent) ---
      sub_filter '/api/v2/${path}/' '/api/v2/';
      sub_filter '/api/v1/${path}/' '/api/v1/';
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

      sabnzbd = {
        enable = true;
        group = "media";
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
        group = "media";
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
            "Session\\DHTEnabled" = false;
            "Session\\PeXEnabled" = false;
            "Session\\LSDEnabled" = false;
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
          database = {
            type = "sqlite";
            dsn = "/data/.state/autobrr/autobrr.db";
          };
          # metricsBasicAuthUsers = "i:$2y$05$yaH6RqWhDQGPvLI7vyVdY.EsH8LBrNaAS30HJwXiCHziIFf7csVbi";
        };
        serviceConfig = {
          User = "autobrr";
          Group = "media";
          ReadWritePaths = [
            "/data/.state/autobrr"
            "/var/lib/autobrr"
          ];
        };
      };

      nginx = {
        enable = lib.mkForce true;
        commonHttpConfig = ''
          map $http_upgrade $connection_upgrade {
            default upgrade;
            ""      close;
          }
        '';
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
              proxyWebsockets = true;
              extraConfig = subpathProxyConfig {
                path = "bazarr";
                port = config.ports.bazarr;
              };
            };
            "/autobrr/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.autobrr}";
              proxyWebsockets = true;
            };
            "/autobrr" = {
              return = "301 /autobrr/";
            };
            "/qbit/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.qbittorrent}/";
              proxyWebsockets = true;
              extraConfig = subpathProxyConfig {
                path = "qbit";
                port = config.ports.qbittorrent;
              };
            };
            "/qbit" = {
              return = "301 /qbit/";
            };

            "/vertex/" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.vertex}/";
              proxyWebsockets = true;
              extraConfig = subpathProxyConfig {
                path = "vertex";
                port = config.ports.vertex;
              };
            };
            "/vertex" = {
              return = "301 /vertex/";
            };
            # Proxy Service Worker to Vertex backend to fix root 404
            "/service-worker.js" = {
              proxyPass = "http://127.0.0.1:${toString config.ports.vertex}/service-worker.js";
              extraConfig = ''
                # Allow cross-scope SW registration if needed, though proxying usually avoids this
                proxy_set_header X-Forwarded-Host $host;
              '';
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
              proxyWebsockets = true;
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
        "d /data/.state/jellyfin 0777 jellyfin media -"
        "d /data/.state/jellyseerr 0777 jellyseerr media -"
        "d /data/.state/sonarr 0777 sonarr media -"
        "d /data/.state/sonarr-anime 0777 sonarr-anime media -"
        "d /data/.state/radarr 0777 radarr media -"
        "d /data/.state/prowlarr 0777 prowlarr media -"
        "d /data/.state/lidarr 0777 lidarr media -"
        "d /data/.state/sabnzbd 0777 sabnzbd media -"
        "d /data/.state/recyclarr 0777 recyclarr media -"
        "d /data/.state/autobrr 0777 autobrr media -"
        "d /data/.state/moviepilot 0777 root media -"
        "d /data/.state/moviepilot/core 0777 root media -"
        "d /data/.state/vertex 0777 root media -"
        "d /data/.state/iyuu 0777 root media -"
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

          media-stack-init = {
            description = "Automated configuration for media stack connections";
            after = [
              "sonarr.service"
              "radarr.service"
              "prowlarr.service"
              "bazarr.service"
              "qbittorrent.service"
              "postgresql-ready.target"
              "autobrr-user-init.service"
            ];
            wants = [
              "sonarr.service"
              "radarr.service"
              "prowlarr.service"
              "bazarr.service"
              "qbittorrent.service"
              "autobrr-user-init.service"
            ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              Restart = "on-failure";
              RestartSec = "30s";
              TimeoutStartSec = "1min";
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
                host="''${service%%:*}"
                path_port="''${service#*:}"
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
                --sonarr-anime-url "http://127.0.0.1:8990/sonarr-anime" \
                --sonarr-anime-key-file "${config.sops.secrets."media/sonarr_api_key".path}" \
                --mteam-rss-file "${config.sops.secrets."media/mteam_rss_url".path}" \
                --pttime-rss-file "${config.sops.secrets."media/pttime_rss_url".path}" \
                --lidarr-url "http://127.0.0.1:${toString config.ports.lidarr}/lidarr" \
                --lidarr-key-file "${config.sops.secrets."media/lidarr_api_key".path}"
            '';
          };

          # Fix autobrr service - Ensure correct User/Group and permissions for /data
          autobrr.serviceConfig = {
            DynamicUser = lib.mkForce false;
            User = lib.mkForce "autobrr";
            Group = lib.mkForce "media";
            ReadWritePaths = [ "/data/.state/autobrr" ];
          };

          # autobrr-user-init = {
          #   description = "Setup Autobrr User";
          #   after = [ "autobrr.service" ];
          #   wants = [ "autobrr.service" ];
          #   wantedBy = [ "multi-user.target" ];
          #   serviceConfig = {
          #     Type = "oneshot";
          #     User = "autobrr";
          #     Group = "media";
          #     WorkingDirectory = "/data/.state/autobrr";
          #   };
          #   script = ''
          #     # Allow autobrr to initialize
          #     sleep 10
          #
          #     PASSWORD=$(cat ${config.sops.secrets."password".path})
          #     CONFIG_FILE="/data/.state/autobrr/config.toml"
          #
          #     # Ensure user exists (idempotent via || echo)
          #     ${pkgs.autobrr}/bin/autobrrctl --config /data/.state/autobrr create-user i <<< "$PASSWORD" || echo "User creation failed or user exists"
          #
          #     # Update metricsBasicAuthUsers in config.toml
          #     if [ -f "$CONFIG_FILE" ]; then
          #       # Use sed to replace the line with the specific hash requested
          #       sed -i "s|metricsBasicAuthUsers = .*|metricsBasicAuthUsers = 'i:\$2y\$05\$yaH6RqWhDQGPvLI7vyVdY.EsH8LBrNaAS30HJwXiCHziIFf7csVbi'|" "$CONFIG_FILE"
          #       echo "Updated metricsBasicAuthUsers in $CONFIG_FILE"
          #     else
          #        echo "Config file not found at $CONFIG_FILE"
          #     fi
          #
          #     # Inject API Key for setup.py
          #     API_KEY=$(cat ${config.sops.secrets."media/autobrr_session_token".path})
          #     DB_FILE="/data/.state/autobrr/autobrr.db"
          #     if [ -f "$DB_FILE" ]; then
          #       ${pkgs.sqlite}/bin/sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO api_key (name, key) VALUES ('setup', '$API_KEY');"
          #       echo "Injected API Key into $DB_FILE"
          #     fi
          #   '';
          # };

          jellyfin.serviceConfig = {
            PrivateUsers = lib.mkForce false;
            UMask = "0002";
          };
          sonarr.serviceConfig.UMask = "0002";
          radarr.serviceConfig.UMask = "0002";
          prowlarr.serviceConfig.UMask = "0002";
          lidarr.serviceConfig.UMask = "0002";
          sabnzbd.serviceConfig.UMask = "0002";
          jellyseerr.serviceConfig.UMask = "0002";
          sonarr-anime.serviceConfig.UMask = "0002";
          bazarr.serviceConfig.UMask = "0002";
          qbittorrent.serviceConfig.UMask = "0002"; # Already has group but ensure umask
          autobrr.serviceConfig.UMask = "0002";
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
          "/data/.state/vertex:/vertex"
          "/data/downloads/torrents:/data/downloads/torrents"
        ];
        environment = {
          TZ = "Asia/Shanghai";
          PORT = toString config.ports.vertex;
          BASE_PATH = "/vertex";
          # USERNAME = "i";
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
