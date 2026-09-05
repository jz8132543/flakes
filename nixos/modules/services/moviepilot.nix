{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.moviepilot;
in
{
  # ═══════════════════════════════════════════════════════════════
  # Options Definition
  # ═══════════════════════════════════════════════════════════════
  options.services.moviepilot = {
    enable = lib.mkEnableOption "MoviePilot NAS Media Library Automation";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "movie.${config.networking.domain}";
      description = "Primary public domain for MoviePilot (defaults to movie.dora.im).";
    };

    package = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/jxxghp/moviepilot:latest";
      description = "MoviePilot OCI container image.";
    };

    webPort = lib.mkOption {
      type = lib.types.port;
      default = config.ports.moviepilot or 3201;
      description = "Web UI port (Nginx reverse proxy in container).";
    };

    backendPort = lib.mkOption {
      type = lib.types.port;
      default = 3202;
      description = "Backend API port (Uvicorn).";
    };

    bigMemoryMode = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable MoviePilot BIG_MEMORY_MODE for high-RAM environments.";
    };

    superuser = {
      username = lib.mkOption {
        type = lib.types.str;
        default = "i";
        description = "MoviePilot superuser account name.";
      };
      passwordSecret = lib.mkOption {
        type = lib.types.str;
        default = "password";
        description = "SOPS secret name for superuser password.";
      };
      apiTokenSecret = lib.mkOption {
        type = lib.types.str;
        default = "media/moviepilot_api_key";
        description = "SOPS secret name for MoviePilot API token.";
      };
    };

    cookiecloud = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable CookieCloud automatic site sync.";
      };
      host = lib.mkOption {
        type = lib.types.str;
        default =
          if (config.services ? cookiecloud && config.services.cookiecloud ? url) then
            config.services.cookiecloud.url
          else
            "https://cookie.${config.networking.domain}";
        description = "CookieCloud server public host URL.";
      };
      key = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "CookieCloud user KEY (plaintext).";
      };
      keySecret = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "SOPS secret name for CookieCloud user KEY.";
      };
      passwordSecret = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "password";
        description = "SOPS secret name for CookieCloud encryption password.";
      };
      interval = lib.mkOption {
        type = lib.types.int;
        default = 1440;
        description = "CookieCloud sync interval in minutes (default 24h).";
      };
      enableLocal = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable local CookieCloud sync (set false to sync with remote CookieCloud server).";
      };
    };

    downloader = {
      type = lib.mkOption {
        type = lib.types.enum [
          "qbittorrent"
          "transmission"
        ];
        default = "qbittorrent";
        description = "Download client type.";
      };
      host = lib.mkOption {
        type = lib.types.str;
        default =
          if (config.nixflix ? urls && config.nixflix.urls ? qbit) then
            config.nixflix.urls.qbit
          else
            "https://qbit.${config.networking.domain}";
        description = "Download client public host URL.";
      };
      username = lib.mkOption {
        type = lib.types.str;
        default = "i";
        description = "Download client username.";
      };
      passwordSecret = lib.mkOption {
        type = lib.types.str;
        default = "password";
        description = "SOPS secret name for download client password.";
      };
      category = lib.mkOption {
        type = lib.types.str;
        default = "moviepilot";
        description = "Default category tag in download client.";
      };
      monitor = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable downloader monitoring in MoviePilot.";
      };
    };

    mediaServer = {
      type = lib.mkOption {
        type = lib.types.enum [
          "jellyfin"
          "emby"
          "plex"
        ];
        default = "jellyfin";
        description = "Media server type.";
      };
      host = lib.mkOption {
        type = lib.types.str;
        default =
          if (config.nixflix ? urls && config.nixflix.urls ? jellyfin) then
            config.nixflix.urls.jellyfin
          else
            "https://jellyfin.${config.networking.domain}/jellyfin";
        description = "Media server public host URL.";
      };
      apiKeySecret = lib.mkOption {
        type = lib.types.str;
        default = "media/jellyfin_api_key";
        description = "SOPS secret name for media server API key.";
      };
      username = lib.mkOption {
        type = lib.types.str;
        default = "i";
        description = "Media server username.";
      };
      passwordSecret = lib.mkOption {
        type = lib.types.str;
        default = "password";
        description = "SOPS secret name for media server password.";
      };
      syncInterval = lib.mkOption {
        type = lib.types.int;
        default = 60;
        description = "Media server library sync interval in minutes.";
      };
    };

    paths = {
      stateDir = lib.mkOption {
        type = lib.types.path;
        default = "/data/.state/moviepilot";
        description = "State directory for MoviePilot (mapped to /config).";
      };
      mediaDir = lib.mkOption {
        type = lib.types.path;
        default = "/data/media";
        description = "Media library root directory (mapped to /media).";
      };
      downloadDir = lib.mkOption {
        type = lib.types.path;
        default = "/data/downloads";
        description = "Download directory (mapped to /downloads).";
      };
      torrentBackupDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/qBittorrent/qBittorrent/BT_backup";
        description = "qBittorrent BT_backup directory for cross-seed and inspection.";
      };
      transferType = lib.mkOption {
        type = lib.types.enum [
          "link"
          "copy"
          "move"
          "softlink"
        ];
        default = "link";
        description = "File transfer type into media library (link = hardlink, 0-second transfer).";
      };
    };

    sites = {
      mteam = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Automatically configure M-Team site using Prowlarr/Nixflix credentials.";
        };
        name = lib.mkOption {
          type = lib.types.str;
          default = "M-Team";
          description = "Site display name in MoviePilot.";
        };
        domain = lib.mkOption {
          type = lib.types.str;
          default = "m-team.cc";
          description = "Site domain identifier.";
        };
        url = lib.mkOption {
          type = lib.types.str;
          default = "https://kp.m-team.cc/";
          description = "Base URL matching Prowlarr indexer.";
        };
        apiKeySecret = lib.mkOption {
          type = lib.types.str;
          default = "media/mteam_api_key";
          description = "SOPS secret name for M-Team API key.";
        };
        priority = lib.mkOption {
          type = lib.types.int;
          default = 1;
          description = "Site download priority order.";
        };
      };
    };

    automation = {
      subscribeSearch = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable periodic subscription backlog search.";
      };
      scrapMetadata = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable media metadata scraping.";
      };
      ocrHost = lib.mkOption {
        type = lib.types.str;
        default = "https://movie-pilot.org";
        description = "OCR recognition service for site captchas.";
      };
      pluginMarket = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "https://github.com/jxxghp/MoviePilot-Plugins"
          "https://github.com/thsrite/MoviePilot-Plugins"
        ];
        description = "Plugin market repository URLs.";
      };
    };
  };

  # ═══════════════════════════════════════════════════════════════
  # Implementation
  # ═══════════════════════════════════════════════════════════════
  config = lib.mkIf cfg.enable {
    # ─────────────────────────────────────────────────────────────
    # OCI Container - MoviePilot
    # ─────────────────────────────────────────────────────────────
    virtualisation.oci-containers.containers.moviepilot = {
      image = cfg.package;
      autoStart = true;

      volumes = [
        "${cfg.paths.stateDir}:/config"
        "${cfg.paths.stateDir}/core:/moviepilot/.cache/ms-playwright"
        "${cfg.paths.mediaDir}:/media"
        "${cfg.paths.downloadDir}:/downloads"
        "${cfg.paths.torrentBackupDir}:/BT_backup:ro"
        "/run/podman/podman.sock:/var/run/docker.sock:ro"
      ];

      environment = {
        TZ = "Asia/Shanghai";
        PUID = "0";
        PGID = "0";
        UMASK = "022";
        CONFIG_DIR = "/config";
        DOWNLOAD_PATH = "/downloads";
        LIBRARY_PATH = "/media";
        TRANSFER_TYPE = cfg.paths.transferType;

        # Web UI & Backend Port
        NGINX_PORT = toString cfg.webPort;
        PORT = toString cfg.backendPort;

        # Superuser
        SUPERUSER = cfg.superuser.username;

        # Performance
        BIG_MEMORY_MODE = if cfg.bigMemoryMode then "true" else "false";

        # Downloader
        DOWNLOADER = cfg.downloader.type;
        DOWNLOADER_MONITOR = if cfg.downloader.monitor then "true" else "false";
        QB_HOST = cfg.downloader.host;
        QB_USER = cfg.downloader.username;
        QB_CATEGORY = cfg.downloader.category;

        # Media Server
        MEDIASERVER = cfg.mediaServer.type;
        MEDIASERVER_SYNC_INTERVAL = toString cfg.mediaServer.syncInterval;
        JELLYFIN_HOST = cfg.mediaServer.host;

        # CookieCloud
        COOKIECLOUD_HOST = cfg.cookiecloud.host;
        COOKIECLOUD_INTERVAL = toString cfg.cookiecloud.interval;
        COOKIECLOUD_ENABLE_LOCAL = if cfg.cookiecloud.enableLocal then "true" else "false";

        # Automation & Features
        SUBSCRIBE_SEARCH = if cfg.automation.subscribeSearch then "true" else "false";
        SCRAP_METADATA = if cfg.automation.scrapMetadata then "true" else "false";
        OCR_HOST = cfg.automation.ocrHost;
        PLUGIN_MARKET = lib.concatStringsSep "," cfg.automation.pluginMarket;
      };

      environmentFiles = [
        config.sops.templates."moviepilot-env".path
      ];

      extraOptions = [
        "--network=host"
        "--hostname=moviepilot"
      ];
    };

    # ─────────────────────────────────────────────────────────────
    # Sops Template for Secrets
    # ─────────────────────────────────────────────────────────────
    sops.templates."moviepilot-env" = {
      content =
        let
          inherit (config.sops) placeholder;
          cookiecloudPasswordLine =
            if (cfg.cookiecloud.enable && cfg.cookiecloud.passwordSecret != null) then
              "COOKIECLOUD_PASSWORD=" + placeholder."${cfg.cookiecloud.passwordSecret}" + "\n"
            else
              "";
          cookiecloudKeyLine =
            if (cfg.cookiecloud.enable && cfg.cookiecloud.keySecret != null) then
              "COOKIECLOUD_KEY=" + placeholder."${cfg.cookiecloud.keySecret}" + "\n"
            else if (cfg.cookiecloud.enable && cfg.cookiecloud.key != null) then
              "COOKIECLOUD_KEY=" + cfg.cookiecloud.key + "\n"
            else
              "";
        in
        ''
          SUPERUSER=${cfg.superuser.username}
          SUPERUSER_PASSWORD=${placeholder."${cfg.superuser.passwordSecret}"}
          API_TOKEN=${placeholder."${cfg.superuser.apiTokenSecret}"}
          QB_PASSWORD=${placeholder."${cfg.downloader.passwordSecret}"}
          JELLYFIN_API_KEY=${placeholder."${cfg.mediaServer.apiKeySecret}"}
          JELLYFIN_PASSWORD=${placeholder."${cfg.mediaServer.passwordSecret}"}
          ${cookiecloudPasswordLine}${cookiecloudKeyLine}
        '';
      owner = "root";
    };

    # ─────────────────────────────────────────────────────────────
    # Data Directories (tmpfiles)
    # ─────────────────────────────────────────────────────────────
    systemd.tmpfiles.settings."moviepilot" = {
      "${cfg.paths.stateDir}".d = {
        mode = "0755";
      };
      "${cfg.paths.stateDir}/core".d = {
        mode = "0755";
      };
      "${cfg.paths.stateDir}/plugins".d = {
        mode = "0755";
      };
      "${cfg.paths.mediaDir}".d = {
        mode = "0755";
      };
      "${cfg.paths.mediaDir}/movies".d = {
        mode = "0755";
      };
      "${cfg.paths.mediaDir}/tv".d = {
        mode = "0755";
      };
      "${cfg.paths.mediaDir}/anime".d = {
        mode = "0755";
      };
      "${cfg.paths.downloadDir}".d = {
        mode = "0755";
      };
      "${cfg.paths.downloadDir}/torrents".d = {
        mode = "0755";
      };
    };

    # ─────────────────────────────────────────────────────────────
    # Declarative MoviePilot Initializer (Sites, Downloader, MediaServer)
    # ─────────────────────────────────────────────────────────────
    systemd.services.moviepilot-init = {
      description = "MoviePilot Declarative State Initializer";
      after = [ "podman-moviepilot.service" ];
      requires = [ "podman-moviepilot.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.python3
        pkgs.sqlite
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        DB_PATH="${cfg.paths.stateDir}/user.db"
        MAX_WAIT=120
        WAITED=0

        echo "Waiting for MoviePilot SQLite database and table schemas to be initialized..."
        while [ $WAITED -lt $MAX_WAIT ]; do
          if [ -f "$DB_PATH" ] && ${pkgs.sqlite}/bin/sqlite3 "$DB_PATH" "SELECT count(*) FROM site;" >/dev/null 2>&1 && ${pkgs.sqlite}/bin/sqlite3 "$DB_PATH" "SELECT count(*) FROM systemconfig;" >/dev/null 2>&1; then
            echo "MoviePilot database and tables are ready."
            break
          fi
          sleep 2
          WAITED=$((WAITED + 2))
        done

        if [ $WAITED -ge $MAX_WAIT ]; then
          echo "Timeout waiting for MoviePilot database initialization."
          exit 1
        fi

        ${lib.optionalString cfg.sites.mteam.enable ''
          export MTEAM_KEY="$(cat ${config.sops.secrets."${cfg.sites.mteam.apiKeySecret}".path})"
        ''}
        export QB_PASSWORD="$(cat ${config.sops.secrets."${cfg.downloader.passwordSecret}".path})"
        export JELLYFIN_API_KEY="$(cat ${config.sops.secrets."${cfg.mediaServer.apiKeySecret}".path})"

        ${pkgs.python3}/bin/python3 - <<'EOF'
        import os
        import json
        import sqlite3

        db = "${cfg.paths.stateDir}/user.db"
        conn = sqlite3.connect(db)
        cur = conn.cursor()

        # 1. Declaratively synchronize M-Team PT Site
        mteam_enabled = ${if cfg.sites.mteam.enable then "True" else "False"}
        mteam_key = os.environ.get("MTEAM_KEY", "").strip()
        if mteam_enabled and mteam_key:
            cur.execute("SELECT id FROM site WHERE domain LIKE '%m-team%' OR name LIKE '%M-Team%'")
            row = cur.fetchone()
            if row:
                cur.execute(
                    """UPDATE site SET
                        name=?, domain=?, url=?, pri=?, apikey=?, is_active=1,
                        limit_interval=COALESCE(limit_interval, 0),
                        limit_count=COALESCE(limit_count, 0),
                        limit_seconds=COALESCE(limit_seconds, 0),
                        proxy=COALESCE(proxy, 0),
                        render=COALESCE(render, 0),
                        public=COALESCE(public, 0)
                    WHERE id=?""",
                    ("${cfg.sites.mteam.name}", "${cfg.sites.mteam.domain}", "${cfg.sites.mteam.url}", ${toString cfg.sites.mteam.priority}, mteam_key, row[0])
                )
                print(f"Declaratively updated M-Team site (id={row[0]}) in MoviePilot database.")
            else:
                cur.execute(
                    """INSERT INTO site (
                        name, domain, url, pri, apikey, is_active,
                        limit_interval, limit_count, limit_seconds, proxy, render, public
                    ) VALUES (?, ?, ?, ?, ?, 1, 0, 0, 0, 0, 0, 0)""",
                    ("${cfg.sites.mteam.name}", "${cfg.sites.mteam.domain}", "${cfg.sites.mteam.url}", ${toString cfg.sites.mteam.priority}, mteam_key)
                )
                print("Declaratively inserted M-Team site into MoviePilot database.")

        # Ensure all sites have valid non-null rate limiter values for Cython safety
        cur.execute(
            """UPDATE site SET
                limit_interval = COALESCE(limit_interval, 0),
                limit_count = COALESCE(limit_count, 0),
                limit_seconds = COALESCE(limit_seconds, 0),
                proxy = COALESCE(proxy, 0),
                render = COALESCE(render, 0),
                public = COALESCE(public, 0)
            """
        )

        # 2. Declaratively synchronize Downloader (qBittorrent)
        qb_password = os.environ.get("QB_PASSWORD", "").strip()
        if "${cfg.downloader.type}" == "qbittorrent":
            cur.execute("SELECT id, value FROM systemconfig WHERE key='Downloaders'")
            row = cur.fetchone()
            try:
                downloaders = json.loads(row[1]) if row and row[1] else []
            except Exception:
                downloaders = []
            qb_conf = {
                "name": "qbittorrent",
                "type": "qbittorrent",
                "default": True,
                "enabled": True,
                "config": {
                    "host": "${cfg.downloader.host}",
                    "username": "${cfg.downloader.username}",
                    "password": qb_password,
                    "category": "${cfg.downloader.category}"
                },
                "path_mapping": [
                    ["${cfg.paths.downloadDir}", "/downloads"]
                ]
            }
            downloaders = [d for d in downloaders if d.get("name") != "qbittorrent"]
            downloaders.append(qb_conf)
            if row:
                cur.execute("UPDATE systemconfig SET value=? WHERE id=?", (json.dumps(downloaders), row[0]))
            else:
                cur.execute("INSERT INTO systemconfig (key, value) VALUES ('Downloaders', ?)", (json.dumps(downloaders),))
            print("Declaratively configured Downloader (qBittorrent) with public URL in MoviePilot systemconfig.")

        # 3. Declaratively synchronize Media Server (Jellyfin)
        jellyfin_key = os.environ.get("JELLYFIN_API_KEY", "").strip()
        if "${cfg.mediaServer.type}" == "jellyfin":
            cur.execute("SELECT id, value FROM systemconfig WHERE key='MediaServers'")
            row = cur.fetchone()
            try:
                mediaservers = json.loads(row[1]) if row and row[1] else []
            except Exception:
                mediaservers = []
            ms_conf = {
                "name": "jellyfin",
                "type": "jellyfin",
                "enabled": True,
                "config": {
                    "host": "${cfg.mediaServer.host}",
                    "apikey": jellyfin_key,
                    "play_host": "${cfg.mediaServer.host}"
                },
                "sync_interval": ${toString cfg.mediaServer.syncInterval}
            }
            mediaservers = [m for m in mediaservers if m.get("name") != "jellyfin"]
            mediaservers.append(ms_conf)
            if row:
                cur.execute("UPDATE systemconfig SET value=? WHERE id=?", (json.dumps(mediaservers), row[0]))
            else:
                cur.execute("INSERT INTO systemconfig (key, value) VALUES ('MediaServers', ?)", (json.dumps(mediaservers),))
            print("Declaratively configured MediaServer (Jellyfin) with public URL in MoviePilot systemconfig.")

        conn.commit()
        conn.close()
        EOF
      '';
    };

    # ─────────────────────────────────────────────────────────────
    # Traefik Routes
    # ─────────────────────────────────────────────────────────────
    services.traefik.proxies = {
      moviepilot = {
        rule = "Host(`${cfg.domain}`) || Host(`moviepilot.${config.networking.domain}`) || Host(`movie.${config.networking.fqdn}`) || Host(`moviepilot.${config.networking.fqdn}`)";
        target = "http://127.0.0.1:${toString cfg.webPort}";
      };
      moviepilot-fqdn = {
        rule = "Host(`${config.networking.fqdn}`) && PathPrefix(`/moviepilot`)";
        target = "http://127.0.0.1:${toString cfg.webPort}";
        middlewares = [ "moviepilot-stripprefix" ];
      };
    };

    services.traefik.dynamicConfigOptions.http.middlewares = {
      moviepilot-stripprefix.stripPrefix.prefixes = [ "/moviepilot" ];
    };
  };
}
