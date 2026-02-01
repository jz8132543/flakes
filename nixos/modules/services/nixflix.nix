# Nixflix Media Stack
# Declarative media server configuration using nixflix
# https://github.com/kiriwalawren/nixflix
#
# Usage in nixos/hosts/{host}/default.nix:
#   (import nixosModules.services.nixflix { })                    # All enabled (default)
#   (import nixosModules.services.nixflix { jellyfin = false; })  # Disable Jellyfin
#   (import nixosModules.services.nixflix { cross-seed = true; }) # Enable cross-seed
#
# Parameters (all default to true except cross-seed):
#   jellyfin, jellyseerr, sonarr, radarr, prowlarr, lidarr,
#   sabnzbd, bazarr, qbittorrent, recyclarr, flaresolverr
#   cross-seed = false (requires torznabUrls configuration)
#
# PT Racing/Seeding Strategy:
# ┌─────────────────────────────────────────────────────────────┐
# │  Autobrr (RSS)  ──→  qBittorrent  ──→  Cross-seed          │
# │       ↓                   ↓                 ↓               │
# │  抢FREE新种         下载/做种        自动辅种到其他站        │
# └─────────────────────────────────────────────────────────────┘
#
# Credentials:
# - Username: i
# - Password: from sops secret "password"
#
# Architecture:
# - Traefik (external) -> nginx (internal, port 8888) -> services
{
  # ═══════════════════════════════════════════════════════════════
  # Component toggles - all default to true except PT tools
  # ═══════════════════════════════════════════════════════════════
  jellyfin ? true,
  jellyseerr ? true,
  sonarr ? true,
  radarr ? true,
  prowlarr ? true,
  lidarr ? true,
  sabnzbd ? true,
  bazarr ? true,
  qbittorrent ? true,
  recyclarr ? true,
  flaresolverr ? true,

  # ═══════════════════════════════════════════════════════════════
  # PT Racing/Seeding Tools
  # ═══════════════════════════════════════════════════════════════
  autobrr ? true, # Auto-grab FREE torrents from RSS
  cross-seed ? true, # Auto cross-seed between PT sites
  iyuu ? true, # IYUUPlus - Reseed automation and PT management
  vertex ? true, # Vertex - Primary PT tool

  # Autobrr RSS configuration - set to true once you've added RSS URLs to sops
  # Required sops secrets: media/mteam_rss_url, media/pttime_rss_url
  autobrrRssConfigured ? false,

  # ═══════════════════════════════════════════════════════════════
  # Smart Torrent Management (qbit-manage replacement)
  # ═══════════════════════════════════════════════════════════════
  # Automatically manage torrents based on performance metrics:
  # - Delete slow uploaders after X hours
  # - Prioritize high-demand (many leechers, few seeders) torrents
  # - Keep disk usage under control
  smartTorrentManagement ? true,

  # Smart management config
  smartConfig ? {
    # Delete torrents with upload speed < X bytes/s for Y hours
    minUploadSpeed = 1024; # 1 KB/s minimum
    slowSeedingHours = 48; # Delete after 48 hours of slow seeding
    # Minimum seeding time before considering deletion (protect new seeds)
    minSeedingHours = 24;
    # Minimum ratio before deletion (protect low-ratio torrents)
    minRatio = 1.0;
    # Maximum disk usage percentage before aggressive cleanup
    maxDiskUsagePercent = 90;
    # Keep torrents with good seeder/leecher ratio (high demand)
    keepHighDemand = true;
    # Run cleanup every N minutes
    cleanupIntervalMinutes = 30;
  },

  # ═══════════════════════════════════════════════════════════════
  # Prowlarr PT indexers
  # Example: [ { name = "M-Team - TP"; apiKey = { _secret = "..."; }; } ]
  # ═══════════════════════════════════════════════════════════════
  prowlarrIndexers ? [ ],
}:
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf optionalAttrs;
  domain = "tv.${config.networking.domain}";
  navHtmlDir = ../../../conf/nixflix;

  # ═══════════════════════════════════════════════════════════════
  # PT Sites Configuration
  # ═══════════════════════════════════════════════════════════════

  # Helper: Check if any PT site is configured
  hasPtSites = prowlarrIndexers != [ ];

  # Service Port Map for Subdomain Routing
  servicePorts = {
    inherit (config.ports) sonarr;
    inherit (config.ports) radarr;
    inherit (config.ports) lidarr;
    inherit (config.ports) prowlarr;
    inherit (config.ports) bazarr;
    inherit (config.ports) jellyseerr;
    inherit (config.ports) sabnzbd;
    inherit (config.ports) qbittorrent;
    inherit (config.ports) autobrr;
    inherit (config.ports) iyuu;
    inherit (config.ports) vertex;
    inherit (config.ports) flaresolverr;
  };

  # qBittorrent Categories
  qbitCategories = {
    "movies-radarr" = "/data/downloads/torrents/movies-radarr";
    "tv-sonarr" = "/data/downloads/torrents/tv-sonarr";
    "music-lidarr" = "/data/downloads/torrents/music-lidarr";
    "prowlarr" = "/data/downloads/torrents/prowlarr";
  };
in
{
  imports = [
    inputs.nixflix.nixosModules.default
  ];

  # ═══════════════════════════════════════════════════════════════
  # Sops Secrets
  # ═══════════════════════════════════════════════════════════════
  sops.secrets = {
    "password" = {
      mode = "0444";
    };
    "media/sonarr_api_key" = {
      mode = "0400";
    };
    "media/radarr_api_key" = {
      mode = "0400";
    };
    "media/prowlarr_api_key" = {
      mode = "0400";
    };
    "media/jellyfin_api_key" = {
      mode = "0400";
    };
    "media/jellyseerr_api_key" = {
      mode = "0400";
    };
    "media/lidarr_api_key" = {
      mode = "0400";
    };
    "media/sabnzbd_api_key" = {
      mode = "0400";
    };
    "media/sabnzbd_nzb_key" = {
      mode = "0400";
    };
  }
  # PT Site secrets - API keys and RSS URLs (RSS contains passkey, must be encrypted)
  // lib.optionalAttrs hasPtSites {
    "media/mteam_api_key" = {
      mode = "0400";
    };
    "media/pttime_api_key" = {
      mode = "0400";
    };
  }
  // lib.optionalAttrs autobrr {
    "autobrr/secret" = {
      mode = "0400";
    };
  }
  // lib.optionalAttrs (autobrr && autobrrRssConfigured) {
    # PT RSS feeds - contain passkey, must be encrypted!
    # Format: https://kp.m-team.cc/rss.php?...&passkey=xxx
    "media/mteam_rss_url" = {
      mode = "0400";
    };
    "media/pttime_rss_url" = {
      mode = "0400";
    };
  };

  # Create media group for shared file access
  users.groups.media = { };

  # Nixflix configuration
  nixflix = {
    enable = true;
    mediaDir = "/data/media";
    stateDir = "/data/.state";
    downloadsDir = "/data/downloads";
    mediaUsers = [ "tippy" ];

    # Use SQLite for all services (no postgres dependency)
    postgres.enable = false;

    # Disable VPN
    mullvad.enable = false;

    # Enable nginx for path rewriting (traefik will proxy to it)
    nginx.enable = true;

    # Theme
    theme = {
      enable = true;
      name = "overseerr";
    };

    # Jellyfin - Media Server
    jellyfin = {
      enable = jellyfin;
      group = "media";
      users.i = {
        password = {
          _secret = config.sops.secrets."password".path;
        };
        policy.isAdministrator = true;
      };
      network = {
        baseUrl = "/jellyfin";
        publishedServerUriBySubnet = [
          "0.0.0.0/0=https://${domain}/jellyfin"
        ];
      };
    };

    # Jellyseerr - Request Management
    jellyseerr = {
      enable = jellyseerr;
      apiKey = {
        _secret = config.sops.secrets."media/jellyseerr_api_key".path;
      };
      # 必须与 jellyfin.network.baseUrl 保持一致
      jellyfin = {
        urlBase = "/jellyfin";
      };
    };

    # Sonarr - TV Series Management
    sonarr = {
      enable = sonarr;
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
        };
      };
    };

    # Radarr - Movie Management
    radarr = {
      enable = radarr;
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
        };
      };
    };

    # Prowlarr - Indexer Management
    prowlarr = {
      enable = prowlarr;
      config = {
        apiKey = {
          _secret = config.sops.secrets."media/prowlarr_api_key".path;
        };
        hostConfig = {
          username = "i";
          password = {
            _secret = config.sops.secrets."password".path;
          };
        };
        # Override applications with correct port URLs (nixflix assumes nginx on port 80)
        applications = lib.mkForce [
          {
            name = "Sonarr";
            implementationName = "Sonarr";
            apiKey = {
              _secret = config.sops.secrets."media/sonarr_api_key".path;
            };
            baseUrl = "http://127.0.0.1:8989/sonarr";
            prowlarrUrl = "http://127.0.0.1:9696/prowlarr";
          }
          {
            name = "Radarr";
            implementationName = "Radarr";
            apiKey = {
              _secret = config.sops.secrets."media/radarr_api_key".path;
            };
            baseUrl = "http://127.0.0.1:7878/radarr";
            prowlarrUrl = "http://127.0.0.1:9696/prowlarr";
          }
          {
            name = "Lidarr";
            implementationName = "Lidarr";
            apiKey = {
              _secret = config.sops.secrets."media/lidarr_api_key".path;
            };
            baseUrl = "http://127.0.0.1:8686/lidarr";
            prowlarrUrl = "http://127.0.0.1:9696/prowlarr";
          }
        ];
        # PT Indexers - configured via prowlarrIndexers parameter
        indexers = prowlarrIndexers;
      };
    };

    # Lidarr - Music Management
    lidarr = {
      enable = lidarr;
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
        };
      };
    };

    # SABnzbd - Usenet Downloader
    sabnzbd = {
      enable = sabnzbd;
      settings = {
        misc = {
          api_key = {
            _secret = config.sops.secrets."media/sabnzbd_api_key".path;
          };
          nzb_key = {
            _secret = config.sops.secrets."media/sabnzbd_nzb_key".path;
          };
          host = "127.0.0.1";
          port = 8090;
          url_base = "/sabnzbd";
          # Allow access from reverse proxy with this hostname
          host_whitelist = domain;
        };
      };
    };

    # Recyclarr - TRaSH Guides sync
    recyclarr = {
      enable = recyclarr;
    };
  };

  # Bazarr - Subtitle Management (using native NixOS service)
  services.bazarr = {
    enable = bazarr;
    group = "media";
    listenPort = 6767;
  };

  # FlareSolverr - Cloudflare bypass
  services.flaresolverr = {
    enable = flaresolverr;
    port = 8191;
  };

  # ═══════════════════════════════════════════════════════════════
  # qBittorrent - Torrent client with VueTorrent UI
  # ═══════════════════════════════════════════════════════════════
  # EXTREME OPTIMIZATION for PT Racing
  # ═══════════════════════════════════════════════════════════════
  services.qbittorrent = {
    enable = qbittorrent;
    group = "media";
    webuiPort = 8080;
    serverConfig = {
      Preferences = {
        WebUI = {
          AlternativeUIEnabled = true;
          RootFolder = "${pkgs.vuetorrent}/share/vuetorrent";
          # Fixed credentials (same as other services)
          Username = "i";
          # Disable CSRF and Host header validation for reverse proxy
          CSRFProtection = false;
          HostHeaderValidation = false;
          # Allow our domain
          ServerDomains = "*";
          # IMPORTANT: Disable SecureCookie when behind reverse proxy
          SecureCookie = false;
          # Disable ClickjackingProtection to allow iframe embedding
          ClickjackingProtection = false;
          # Disable local host auth - we handle auth at nginx/traefik level
          LocalHostAuth = false;
          # Allow connections from reverse proxy subnet
          AuthSubnetWhitelistEnabled = true;
          AuthSubnetWhitelist = "127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16";
        };
        Downloads = {
          SavePath = "/data/downloads/torrents";
          TempPath = "/data/downloads/torrents/.incomplete";
          TempPathEnabled = true;
        };
        # ─────────────────────────────────────────────────────────
        # Network Optimization for PT Racing
        # ─────────────────────────────────────────────────────────
        Connection = {
          # Maximum connections (higher = more potential peers)
          GlobalMaxConnections = 4000;
          MaxConnectionsPerTorrent = 500;
          GlobalMaxUploads = 200;
          MaxUploadsPerTorrent = 50;
          # Resolve countries for better peer management
          ResolvePeerCountries = true;
        };
        # Queueing - Critical for racing!
        Queueing = {
          # Queue torrents (prevent overload)
          QueueingEnabled = true;
          # Max active downloads - adjust based on bandwidth
          MaxActiveDownloads = 20;
          # Max active uploads - we want to seed A LOT
          MaxActiveUploads = 100;
          # Max active torrents overall
          MaxActiveTorrents = 120;
          # Don't count slow torrents towards limits
          IgnoreSlowTorrentsForQueueing = true;
          # Slow torrent thresholds
          SlowTorrentDownloadRateThreshold = 10; # KB/s
          SlowTorrentUploadRateThreshold = 10; # KB/s
          SlowTorrentInactiveTimer = 60; # seconds
        };
      };
      BitTorrent = {
        # Default save path
        "Session\\DefaultSavePath" = "/data/downloads/torrents";
        "Session\\TempPath" = "/data/downloads/torrents/.incomplete";
        "Session\\TempPathEnabled" = true;

        # ─────────────────────────────────────────────────────────
        # EXTREME Performance Tuning
        # ─────────────────────────────────────────────────────────

        # === Protocol Settings ===
        # Enable all protocols for maximum connectivity
        "Session\\BTProtocol" = "Both"; # TCP + uTP

        # === Connection Limits ===
        "Session\\MaxConnections" = 4000;
        "Session\\MaxConnectionsPerTorrent" = 500;
        "Session\\MaxUploads" = 200;
        "Session\\MaxUploadsPerTorrent" = 50;
        # Disable half-open connections limit (aggressive mode)
        "Session\\MaxHalfOpenConnections" = 100;

        # === Upload Optimization (CRITICAL for PT) ===
        # No upload limit
        "Session\\GlobalMaxUploadSpeed" = 0;
        # Prioritize first/last piece (for media streaming, but not critical for PT)
        "Session\\PrioritizeFirstAndLast" = false;
        # Super seeding mode (increase upload efficiency)
        "Session\\EnableSuperSeeding" = true;
        # Upload choking algorithm: Fastest upload (aggressive)
        "Session\\ChokingAlgorithm" = "FastestUpload";
        # Seed choking algorithm: Anti-leech (protect against hit-and-runners)
        "Session\\SeedChokingAlgorithm" = "AntiLeech";
        # Upload slots behavior: Upload rate based (more slots for fast uploaders)
        "Session\\UploadSlotsBehavior" = "UploadRateBased";

        # === Download Optimization ===
        # No download limit for racing
        "Session\\GlobalMaxDownloadSpeed" = 0;
        # Pre-allocate files (reduces fragmentation, faster writes)
        "Session\\PreallocationEnabled" = true;
        # Coalesce reads/writes (better disk performance)
        "Session\\CoalesceReadsAndWrites" = true;
        # Piece extent affinity (minimize seeks)
        "Session\\PieceExtentAffinity" = true;
        # Send buffer watermark (tune for high-speed connections)
        "Session\\SendBufferWatermark" = 5120; # 5 MB
        "Session\\SendBufferLowWatermark" = 1024; # 1 MB
        "Session\\SendBufferWatermarkFactor" = 250; # 250%
        # Socket buffer sizes (larger = better for high latency)
        "Session\\SocketSendBufferSize" = 0; # 0 = auto (OS default)
        "Session\\SocketReceiveBufferSize" = 0;

        # === Disk I/O Optimization ===
        # Async I/O threads (increase for SSD/NVMe)
        "Session\\AsyncIOThreadsCount" = 16;
        # Hashing threads (increase for multi-core CPUs)
        "Session\\HashingThreadsCount" = 4;
        # Disk cache (0 = auto-detect based on RAM)
        "Session\\DiskCacheSize" = 512; # 512 MB explicit cache
        "Session\\DiskCacheTTL" = 120; # 2 minutes TTL
        # Use OS cache too
        "Session\\UseOSCache" = true;
        # Disk queue size (larger = more buffering)
        "Session\\DiskQueueSize" = 2097152; # 2 MB

        # === Peer Discovery & DHT ===
        # Enable DHT for public trackers (PT usually disables, but keep for fallback)
        "Session\\DHTEnabled" = false; # PT sites usually forbid
        "Session\\PeXEnabled" = false; # PT sites usually forbid
        "Session\\LSDEnabled" = false; # Not useful for cloud servers

        # === NAT/Port Forwarding (for both public and NAT) ===
        # Enable UPnP/NAT-PMP for NAT traversal
        "Session\\UseUPnP" = true;
        "Session\\UseNATPMP" = true;
        # Listening port (will be configured separately)
        "Session\\Port" = 51413;
        # Use random port if default fails
        "Session\\UseRandomPort" = false;

        # === Encryption (PT compatible) ===
        # Prefer encryption, but allow unencrypted for compatibility
        "Session\\Encryption" = 1; # 0=prefer, 1=force, 2=disable

        # === Tracker Optimization ===
        # Stop tracker timeout (more patient with slow trackers)
        "Session\\StopTrackerTimeout" = 10;
        # Announce to all trackers in a tier
        "Session\\AnnounceToAllTrackers" = true;
        # Announce to all tiers
        "Session\\AnnounceToAllTiers" = true;
        # Tracker exchange (find more peers)
        "Session\\TrackerExchangeEnabled" = true;

        # === Speed/Anti-Stall ===
        # uTP rate limiting (disabled for maximum speed)
        "Session\\uTPRateLimited" = false;
        # Ignore slow torrents in auto-management
        "Session\\IgnoreLimitsOnLocalNetwork" = true;
        # Auto-ban peers with bad behavior
        "Session\\BanIpOnAntiSpeedLimitViolation" = true;

        # === Seeding Behavior ===
        # No ratio limit (seed forever for PT)
        "Session\\GlobalMaxRatio" = -1;
        # No seeding time limit
        "Session\\GlobalMaxSeedingMinutes" = -1;
        # When ratio reached: Do nothing (keep seeding)
        "Session\\MaxRatioAction" = 0;

        # === Queue Management ===
        "Session\\QueueingSystemEnabled" = true;
        "Session\\MaxActiveDownloads" = 20;
        "Session\\MaxActiveUploads" = 100;
        "Session\\MaxActiveTorrents" = 120;
        "Session\\IgnoreSlowTorrentsForQueueing" = true;
        "Session\\SlowTorrentsDownloadRate" = 10;
        "Session\\SlowTorrentsUploadRate" = 10;
        "Session\\SlowTorrentsInactivityTimer" = 60;

        # === IP Filtering ===
        # Disable IP filtering (PT peers are trusted)
        "Session\\IPFilteringEnabled" = false;
      };
      # Disable session timeout
      Application = {
        "GUI\\SessionTimeout" = "-1";
      };
      # === Advanced Settings ===
      Advanced = {
        # Recheck on completion (ensure data integrity)
        "RecheckOnCompletion" = false; # Disabled for speed
        # Tracker list URL (update periodically)
        # "trackerListURL" = "";  # PT doesn't need public trackers
      };
    };
  };

  # ─────────────────────────────────────────────────────────────────
  # Additional System Tuning for qBittorrent
  # ─────────────────────────────────────────────────────────────────
  # Note: Most network tuning is already in nixos/modules/base/network.nix
  # These are additional settings specific to torrent workloads
  boot.kernel.sysctl = lib.mkIf qbittorrent {
    # Additional orphaned sockets limit
    "net.ipv4.tcp_max_orphans" = lib.mkDefault 65535;
    # Enable SACK (selective ACK) for better recovery
    "net.ipv4.tcp_sack" = lib.mkDefault 1;
    # Enable TCP timestamps
    "net.ipv4.tcp_timestamps" = lib.mkDefault 1;
    # Optional memory max
    "net.core.optmem_max" = lib.mkDefault 65535;
    # Open file limits (for many connections)
    "fs.nr_open" = lib.mkDefault 2097152;
    # TCP/UDP memory pools
    "net.ipv4.tcp_mem" = lib.mkDefault "786432 1048576 134217728";
    "net.ipv4.udp_mem" = lib.mkDefault "786432 1048576 134217728";
  };

  # Create /data directory structure for nixflix
  systemd.tmpfiles.settings."nixflix-data" = {
    # Base /data directory
    "/data".d = {
      user = "root";
      group = "media";
      mode = "0775";
    };
    # Media directory
    "/data/media".d = {
      user = "root";
      group = "media";
      mode = "0775";
    };
    # Downloads directory
    "/data/downloads".d = {
      user = "root";
      group = "media";
      mode = "0775";
    };
    # Usenet downloads (for SABnzbd)
    "/data/downloads/usenet".d = {
      user = "sabnzbd";
      group = "media";
      mode = "0775";
    };
    "/data/downloads/usenet/incomplete".d = {
      user = "sabnzbd";
      group = "media";
      mode = "0775";
    };
    "/data/downloads/usenet/complete".d = {
      user = "sabnzbd";
      group = "media";
      mode = "0775";
    };
    # State directory (hidden)
    "/data/.state".d = {
      user = "root";
      group = "media";
      mode = "0775";
    };
    # Torrents directory (base)
    "/data/downloads/torrents".d = {
      user = "qbittorrent";
      group = "media";
      mode = "0775";
    };
    "/data/downloads/torrents/.incomplete".d = {
      user = "qbittorrent";
      group = "media";
      mode = "0775";
    };
    # Category directories for *arr apps - these are where downloads go
    "/data/downloads/torrents/tv-sonarr".d = {
      user = "qbittorrent";
      group = "media";
      mode = "0775";
    };
    "/data/downloads/torrents/movies-radarr".d = {
      user = "qbittorrent";
      group = "media";
      mode = "0775";
    };
    "/data/downloads/torrents/music-lidarr".d = {
      user = "qbittorrent";
      group = "media";
      mode = "0775";
    };
    "/data/downloads/torrents/prowlarr".d = {
      user = "qbittorrent";
      group = "media";
      mode = "0775";
    };
    # Legacy torrents directory (keep for backwards compatibility)
    "/data/torrents".d = {
      user = "qbittorrent";
      group = "media";
      mode = "0775";
    };
    "/data/torrents/downloading".d = {
      user = "qbittorrent";
      group = "media";
      mode = "0775";
    };
    "/data/torrents/completed".d = {
      user = "qbittorrent";
      group = "media";
      mode = "0775";
    };
  };

  # Service state directories under /data/.state
  systemd.tmpfiles.settings."nixflix-state" = {
    "/data/.state/jellyfin".d = {
      user = "jellyfin";
      group = "media";
      mode = "0750";
    };
    "/data/.state/jellyseerr".d = {
      user = "jellyseerr";
      group = "media";
      mode = "0750";
    };
    "/data/.state/sonarr".d = {
      user = "sonarr";
      group = "media";
      mode = "0750";
    };
    "/data/.state/radarr".d = {
      user = "radarr";
      group = "media";
      mode = "0750";
    };
    "/data/.state/prowlarr".d = {
      user = "prowlarr";
      group = "media";
      mode = "0750";
    };
    "/data/.state/lidarr".d = {
      user = "lidarr";
      group = "media";
      mode = "0750";
    };
    "/data/.state/sabnzbd".d = {
      user = "sabnzbd";
      group = "media";
      mode = "0750";
    };
    "/data/.state/recyclarr".d = {
      user = "recyclarr";
      group = "media";
      mode = "0750";
    };
    # Native NixOS services (not managed by nixflix stateDir)
    "/var/lib/bazarr".d = {
      user = "bazarr";
      group = "media";
      mode = "0750";
    };
    "/var/lib/qbittorrent".d = {
      user = "qbittorrent";
      group = "media";
      mode = "0750";
    };
  };

  # Configure nginx to listen ONLY on internal port (traefik will proxy to it)
  # Use mkForce to override nixflix default listen on port 80
  services.nginx.virtualHosts.localhost = {
    listen = lib.mkForce [
      {
        addr = "127.0.0.1";
        port = config.ports.nginx;
      }
    ];
    # Make nginx use correct external domain for redirects
    serverName = lib.mkForce domain;
    extraConfig = ''
      # Don't include port in redirects since we're behind traefik
      absolute_redirect off;
    '';
    # Add locations for services not managed by nixflix
    locations = {
      # Root path - navigation page
      "/" = {
        extraConfig = ''
          root ${navHtmlDir};
          try_files /nav.html =404;
          default_type text/html;
        '';
      };
      "/bazarr" = {
        proxyPass = "http://127.0.0.1:6767";
        recommendedProxySettings = true;
        extraConfig = ''
          proxy_redirect off;
        '';
      };
      # Autobrr
      "/autobrr" = {
        proxyPass = "http://127.0.0.1:${toString config.ports.autobrr}";
        recommendedProxySettings = true;
        extraConfig = ''
          proxy_redirect off;
        '';
      };
      # Iyuu
      "/iyuu" = {
        proxyPass = "http://127.0.0.1:${toString config.ports.iyuu}";
        recommendedProxySettings = true;
        extraConfig = ''
          proxy_redirect off;
          sub_filter_once off;
          sub_filter 'href="/' 'href="/iyuu/';
          sub_filter "href='/" "href='/iyuu/";
          sub_filter 'src="/' 'src="/iyuu/';
          sub_filter "src='/" "src='/iyuu/";
          sub_filter 'action="/' 'action="/iyuu/';
          sub_filter 'url(/' 'url(/iyuu/';
        '';
      };
      # Vertex
      "/vertex" = {
        proxyPass = "http://127.0.0.1:${toString config.ports.vertex}";
        recommendedProxySettings = true;
        extraConfig = ''
          proxy_redirect off;
          sub_filter_once off;
          sub_filter 'href="/' 'href="/vertex/';
          sub_filter "href='/" "href='/vertex/";
          sub_filter 'src="/' 'src="/vertex/';
          sub_filter "src='/" "src='/vertex/";
          sub_filter 'action="/' 'action="/vertex/';
          sub_filter 'url(/' 'url(/vertex/';
        '';
      };
      # Redirect /qbittorrent to /qbittorrent/ (with trailing slash)
      "= /qbittorrent" = {
        return = "301 /qbittorrent/";
      };
      # qBittorrent needs special handling - it doesn't support subpath
      # We need to proxy both /qbittorrent/ and its static assets
      "/qbittorrent/" = {
        proxyPass = "http://127.0.0.1:8080/";
        recommendedProxySettings = true;
        extraConfig = ''
          # Cookie handling - CRITICAL for login to work
          proxy_cookie_path / /qbittorrent/;
          proxy_cookie_flags ~ nosecure samesite=lax;

          # Pass correct headers for auth
          proxy_set_header X-Forwarded-Host $host;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header Cookie $http_cookie;
          proxy_set_header Origin "";
          proxy_set_header Referer "";

          # Rewrite redirects
          proxy_redirect / /qbittorrent/;
          proxy_redirect http://127.0.0.1:8080/ /qbittorrent/;

          # Rewrite HTML content to fix asset paths
          sub_filter_once off;
          sub_filter_types text/html text/css application/javascript application/json;
          sub_filter 'href="/' 'href="/qbittorrent/';
          sub_filter "href='/" "href='/qbittorrent/";
          sub_filter 'src="/' 'src="/qbittorrent/';
          sub_filter "src='/" "src='/qbittorrent/";
          sub_filter 'action="/' 'action="/qbittorrent/';
          sub_filter 'url(/' 'url(/qbittorrent/';
          sub_filter '"/api' '"/qbittorrent/api';
          sub_filter "'/api" "'/qbittorrent/api";
          sub_filter 'fetch("/' 'fetch("/qbittorrent/';
          sub_filter "fetch('/" "fetch('/qbittorrent/";
        '';
      };
      # Catch qBittorrent static assets that don't have /qbittorrent prefix
      "~ ^/(scripts|css|images|icons)/.*" = {
        proxyPass = "http://127.0.0.1:8080";
        recommendedProxySettings = true;
      };
      "/api/v2" = {
        proxyPass = "http://127.0.0.1:8080";
        recommendedProxySettings = true;
      };
    }
    // optionalAttrs autobrr {
      # Autobrr - Auto racing/seeding for PT sites
      "/autobrr" = {
        proxyPass = "http://127.0.0.1:${toString config.ports.autobrr}";
        recommendedProxySettings = true;
        extraConfig = ''
          proxy_redirect off;
        '';
      };
    };
  };

  # Traefik routes all media requests to nginx
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      # Main Landing Page
      nixflix = {
        rule = "Host(`${domain}`)";
        entryPoints = [ "https" ];
        service = "nixflix-nginx";
        tls.certResolver = "zerossl";
      };
      # FQDN access for legacy support (subpath routing)
      nixflix-fqdn = {
        rule = "Host(`${config.networking.fqdn}`) && (PathPrefix(`/jellyfin`) || PathPrefix(`/jellyseerr`) || PathPrefix(`/sonarr`) || PathPrefix(`/radarr`) || PathPrefix(`/prowlarr`) || PathPrefix(`/lidarr`) || PathPrefix(`/bazarr`) || PathPrefix(`/sabnzbd`) || PathPrefix(`/qbittorrent`) || PathPrefix(`/autobrr`) || PathPrefix(`/iyuu`) || PathPrefix(`/vertex`))";
        entryPoints = [ "https" ];
        service = "nixflix-nginx";
        tls.certResolver = "zerossl";
      };
    }
    # Individual Subdomain Routers (ROOT FIX for 418/redirect issues)
    // (lib.mapAttrs' (
      name: _port:
      lib.nameValuePair "nixflix-${name}" {
        rule = "Host(`${name}.${domain}`)";
        entryPoints = [ "https" ];
        service = "nixflix-${name}";
        tls.certResolver = "zerossl";
      }
    ) servicePorts);
    services = {
      nixflix-nginx.loadBalancer.servers = [
        { url = "http://127.0.0.1:${toString config.ports.nginx}"; }
      ];
    }
    // (lib.mapAttrs' (
      name: port:
      lib.nameValuePair "nixflix-${name}" {
        loadBalancer.servers = [ { url = "http://127.0.0.1:${toString port}"; } ];
      }
    ) servicePorts);
  };

  # Persistence for nixflix services
  environment.global-persistence.directories = [
    # nixflix data directory (contains media, downloads, and state)
    "/data"
    # Native NixOS services (not managed by nixflix)
    "/var/lib/bazarr"
    "/var/lib/qbittorrent"
  ]
  ++ lib.optional autobrr "/var/lib/autobrr"
  ++ lib.optional cross-seed "/var/lib/cross-seed";

  # Restic backup for critical config (not media files)
  services.restic.backups.borgbase.paths = [
    # # Jellyfin config (exclude cache and transcodes)
    # "/var/lib/jellyfin/config"
    # "/var/lib/jellyfin/data"
    # # Arr stack configs
    # "/var/lib/sonarr"
    # "/var/lib/radarr"
    # "/var/lib/prowlarr"
    # "/var/lib/lidarr"
    # "/var/lib/bazarr"
    # # Request manager
    # "/var/lib/jellyseerr"
    # # Download clients
    # "/var/lib/sabnzbd"
    # "/var/lib/qbittorrent"
  ];

  # Create postgresql-ready.target for nixflix compatibility
  # This target is used by nixflix services to wait for PostgreSQL to be ready
  systemd.targets.postgresql-ready = {
    description = "PostgreSQL is ready for connections";
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];
  };

  # Add restart on failure for all nixflix services
  systemd.services = {
    # Main services - restart on failure
    jellyfin.serviceConfig.Restart = lib.mkForce "on-failure";
    jellyseerr.serviceConfig.Restart = lib.mkForce "on-failure";
    sonarr.serviceConfig.Restart = lib.mkForce "on-failure";
    radarr.serviceConfig.Restart = lib.mkForce "on-failure";
    prowlarr.serviceConfig.Restart = lib.mkForce "on-failure";
    lidarr.serviceConfig.Restart = lib.mkForce "on-failure";
    sabnzbd.serviceConfig.Restart = lib.mkForce "on-failure";
    bazarr.serviceConfig.Restart = lib.mkForce "on-failure";
    qbittorrent.serviceConfig.Restart = lib.mkForce "on-failure";
    flaresolverr.serviceConfig.Restart = lib.mkForce "on-failure";

    # Oneshot services - add timeout to prevent hanging forever
    # Arr config services
    sonarr-config.serviceConfig.TimeoutStartSec = "5min";
    radarr-config.serviceConfig.TimeoutStartSec = "5min";
    prowlarr-config.serviceConfig.TimeoutStartSec = "5min";
    lidarr-config.serviceConfig.TimeoutStartSec = "5min";

    # Arr root folders services
    sonarr-rootfolders.serviceConfig.TimeoutStartSec = "5min";
    radarr-rootfolders.serviceConfig.TimeoutStartSec = "5min";
    lidarr-rootfolders.serviceConfig.TimeoutStartSec = "5min";

    # Arr download clients services
    sonarr-downloadclients.serviceConfig.TimeoutStartSec = "5min";
    radarr-downloadclients.serviceConfig.TimeoutStartSec = "5min";
    prowlarr-downloadclients.serviceConfig.TimeoutStartSec = "5min";
    lidarr-downloadclients.serviceConfig.TimeoutStartSec = "5min";

    # Arr delay profiles services
    sonarr-delayprofiles.serviceConfig.TimeoutStartSec = "5min";
    radarr-delayprofiles.serviceConfig.TimeoutStartSec = "5min";
    lidarr-delayprofiles.serviceConfig.TimeoutStartSec = "5min";

    # Prowlarr additional services
    prowlarr-applications.serviceConfig.TimeoutStartSec = "5min";

    # Jellyfin setup services
    jellyfin-setup-wizard.serviceConfig.TimeoutStartSec = "5min";
    jellyfin-system-config.serviceConfig.TimeoutStartSec = "5min";
    jellyfin-encoding-config.serviceConfig.TimeoutStartSec = "5min";
    jellyfin-branding-config.serviceConfig.TimeoutStartSec = "5min";
    jellyfin-libraries.serviceConfig.TimeoutStartSec = "5min";

    # Jellyseerr setup services
    jellyseerr-setup.serviceConfig.TimeoutStartSec = "5min";
    jellyseerr-sonarr.serviceConfig.TimeoutStartSec = "5min";
    jellyseerr-radarr.serviceConfig.TimeoutStartSec = "5min";
    jellyseerr-libraries.serviceConfig.TimeoutStartSec = "5min";

    # SABnzbd categories
    sabnzbd-categories.serviceConfig.TimeoutStartSec = "5min";

    # Recyclarr
    recyclarr.serviceConfig.TimeoutStartSec = "10min";

    # qBittorrent categories configuration
    # Categories are stored in categories.json, not qBittorrent.conf
    qbittorrent-categories = mkIf qbittorrent {
      description = "Configure qBittorrent categories for *arr apps";
      wantedBy = [ "multi-user.target" ];
      after = [ "qbittorrent.service" ];
      wants = [ "qbittorrent.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "qbittorrent";
        Group = "media";
      };
      script = ''
        CAT_FILE="/var/lib/qBittorrent/qBittorrent/config/categories.json"
        mkdir -p "$(dirname "$CAT_FILE")"
        echo '${
          builtins.toJSON (lib.mapAttrs (_name: path: { save_path = path; }) qbitCategories)
        }' > "$CAT_FILE"
      '';
    };

    # qBittorrent password setup service
    # This sets the password from sops secret on first run
    qbittorrent-password = mkIf qbittorrent {
      description = "Set qBittorrent WebUI password";
      wantedBy = [ "multi-user.target" ];
      after = [ "qbittorrent.service" ];
      wants = [ "qbittorrent.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [
        pkgs.python3
        pkgs.coreutils
      ];
      script = ''
                CONFIG_FILE="/var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf"
                PASSWORD_FILE="${config.sops.secrets."password".path}"
                
                # Wait for config file to exist
                for i in {1..30}; do
                  if [ -f "$CONFIG_FILE" ]; then break; fi
                  sleep 2
                done
                
                if [ ! -f "$CONFIG_FILE" ]; then
                  echo "Config file not found, skipping password setup"
                  exit 0
                fi
                
                # Check if password is already set with PBKDF2
                if grep -q "WebUI\\\\Password_PBKDF2" "$CONFIG_FILE" 2>/dev/null; then
                  echo "Password already configured, skipping"
                  exit 0
                fi
                
                if [ ! -f "$PASSWORD_FILE" ]; then
                  echo "Password file not found"
                  exit 1
                fi
                
                export PASSWORD=$(cat "$PASSWORD_FILE")
                
                # Generate PBKDF2 hash
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
                
                # Stop qBittorrent to modify config
                systemctl stop qbittorrent.service || true
                sleep 2
                
                # Add password to config
                if ! grep -q "\[Preferences\]" "$CONFIG_FILE"; then
                  echo "[Preferences]" >> "$CONFIG_FILE"
                fi
                
                # Remove old password entries if they exist
                sed -i '/WebUI\\Password_PBKDF2/d' "$CONFIG_FILE"
                
                # Add new password after [Preferences] section or WebUI section
                sed -i "/\[Preferences\]/a WebUI\\\\Password_PBKDF2=$HASH" "$CONFIG_FILE"
                
                echo "qBittorrent password configured"
                
                # Restart qBittorrent
                systemctl start qbittorrent.service
      '';
    };
  }
  // optionalAttrs cross-seed {
    # Cross-seed service for automatic cross-seeding between PT sites
    cross-seed = {
      description = "Cross-seed - Automatic torrent cross-seeding";
      after = [ "network.target" ] ++ lib.optional qbittorrent "qbittorrent.service";
      wants = lib.optional qbittorrent "qbittorrent.service";
      wantedBy = [ "multi-user.target" ];
      environment.HOME = "/var/lib/cross-seed";
      serviceConfig = {
        Type = "simple";
        User = "qbittorrent";
        Group = "media";
        ExecStart = "${pkgs.cross-seed}/bin/cross-seed daemon";
        Restart = "on-failure";
        RestartSec = "10s";
        StateDirectory = "cross-seed";
        WorkingDirectory = "/var/lib/cross-seed";
      };
    };
  }
  // optionalAttrs iyuu {
    # ═══════════════════════════════════════════════════════════
    # IYUU Plus - Reseed Automation and PT Management
    # ═══════════════════════════════════════════════════════════
    iyuu = {
      description = "IYUUPlus Service";
      after = [
        "network.target"
        "mysql.service"
      ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
        gitMinimal
        php83
        coreutils
      ];
      serviceConfig = {
        Type = "simple";
        User = "iyuu";
        Group = "media";
        WorkingDirectory = "/var/lib/iyuu";
        ExecStart = "${pkgs.php83}/bin/php start.php start -d";
        Restart = "always";
        RestartSec = "5";
      };
      preStart = ''
        if [ -e .git ]; then
          ${pkgs.gitMinimal}/bin/git fetch --all
          ${pkgs.gitMinimal}/bin/git reset --hard origin/master
        else
          ${pkgs.gitMinimal}/bin/git clone https://github.com/ledccn/iyuuplus-dev.git .
        fi
        # Fixed Targeted Sed for listen address using port variable
        if [ -f config/server.php ]; then
          sed -E -i "s/'listen'[[:space:]]*=>[[:space:]]*'[^']*'/'listen' => 'http:\/\/127.0.0.1:${toString config.ports.iyuu}'/g" config/server.php
        fi
        # Install .env file from secrets
        if [ -f ${config.sops.templates."iyuu-env".path} ]; then
          install -Dm644 ${config.sops.templates."iyuu-env".path} .env
        fi
      '';
    };
  }
  // optionalAttrs smartTorrentManagement {
    # ═══════════════════════════════════════════════════════════
    # Smart Torrent Management
    # ═══════════════════════════════════════════════════════════
    # Custom script that manages torrents based on performance metrics.
    # This replaces qbit_manage with a NixOS-native solution.
    #
    # Features:
    # - Delete slow seeders (low upload speed for extended time)
    # - Protect high-demand torrents (many leechers, few seeders)
    # - Protect new torrents (minimum seeding time)
    # - Disk usage management (aggressive cleanup when full)
    # - Tag-based organization
    #
    qbit-smart-manage = mkIf qbittorrent {
      description = "Smart qBittorrent torrent management";
      after = [ "qbittorrent.service" ];
      wants = [ "qbittorrent.service" ];
      path = [
        pkgs.curl
        pkgs.jq
        pkgs.coreutils
        pkgs.bc
        pkgs.gawk
      ];

      serviceConfig = {
        Type = "oneshot";
        User = "qbittorrent";
        Group = "media";
      };

      script = ''
        #!/usr/bin/env bash
        set -euo pipefail

        # ─────────────────────────────────────────────────────────────
        # Configuration (from Nix)
        # ─────────────────────────────────────────────────────────────
        QBIT_URL="http://127.0.0.1:8080"
        MIN_UPLOAD_SPEED=${toString smartConfig.minUploadSpeed}       # bytes/s
        SLOW_SEEDING_HOURS=${toString smartConfig.slowSeedingHours}   # hours
        MIN_SEEDING_HOURS=${toString smartConfig.minSeedingHours}     # hours
        MIN_RATIO=${toString smartConfig.minRatio}                    # ratio
        MAX_DISK_PERCENT=${toString smartConfig.maxDiskUsagePercent}  # percent
        KEEP_HIGH_DEMAND=${if smartConfig.keepHighDemand then "true" else "false"}

        # Convert hours to seconds
        SLOW_SEEDING_SECS=$((SLOW_SEEDING_HOURS * 3600))
        MIN_SEEDING_SECS=$((MIN_SEEDING_HOURS * 3600))

        echo "═══════════════════════════════════════════════════════════"
        echo "Smart Torrent Management - $(date)"
        echo "═══════════════════════════════════════════════════════════"

        # ─────────────────────────────────────────────────────────────
        # Check disk usage
        # ─────────────────────────────────────────────────────────────
        DISK_USAGE=$(df /data | awk 'NR==2 {print $5}' | tr -d '%')
        echo "Disk usage: $DISK_USAGE%"

        if [ "$DISK_USAGE" -ge "$MAX_DISK_PERCENT" ]; then
          echo "⚠️  Disk usage critical! Enabling aggressive cleanup..."
          AGGRESSIVE_MODE=true
          # In aggressive mode, reduce minimum seeding time
          MIN_SEEDING_SECS=$((MIN_SEEDING_SECS / 2))
        else
          AGGRESSIVE_MODE=false
        fi

        # ─────────────────────────────────────────────────────────────
        # Get all torrents from qBittorrent
        # ─────────────────────────────────────────────────────────────
        TORRENTS=$(curl -sf "$QBIT_URL/api/v2/torrents/info" || echo "[]")
        TORRENT_COUNT=$(echo "$TORRENTS" | jq 'length')
        echo "Total torrents: $TORRENT_COUNT"

        if [ "$TORRENT_COUNT" -eq 0 ]; then
          echo "No torrents found, exiting."
          exit 0
        fi

        # ─────────────────────────────────────────────────────────────
        # Analyze and manage each torrent
        # ─────────────────────────────────────────────────────────────
        DELETED=0
        PROTECTED=0
        NOW=$(date +%s)

        echo "$TORRENTS" | jq -c '.[]' | while read -r torrent; do
          HASH=$(echo "$torrent" | jq -r '.hash')
          NAME=$(echo "$torrent" | jq -r '.name' | cut -c1-50)
          STATE=$(echo "$torrent" | jq -r '.state')
          RATIO=$(echo "$torrent" | jq -r '.ratio')
          UPSPEED=$(echo "$torrent" | jq -r '.upspeed')
          SEEDING_TIME=$(echo "$torrent" | jq -r '.seeding_time')
          NUM_SEEDS=$(echo "$torrent" | jq -r '.num_complete')
          NUM_LEECH=$(echo "$torrent" | jq -r '.num_incomplete')
          ADDED_ON=$(echo "$torrent" | jq -r '.added_on')
          SIZE=$(echo "$torrent" | jq -r '.size')

          # Skip if not seeding
          if [ "$STATE" != "uploading" ] && [ "$STATE" != "stalledUP" ]; then
            continue
          fi

          # Calculate demand ratio (leechers / seeders)
          # Higher = more demand = keep longer
          if [ "$NUM_SEEDS" -gt 0 ]; then
            DEMAND_RATIO=$(echo "scale=2; $NUM_LEECH / $NUM_SEEDS" | bc -l 2>/dev/null || echo "0")
          else
            DEMAND_RATIO="999"  # No seeders = infinite demand
          fi

          # ─────────────────────────────────────────────────────────
          # Protection checks
          # ─────────────────────────────────────────────────────────
          PROTECTED_REASON=""

          # Protect if seeding time is too short
          if [ "$SEEDING_TIME" -lt "$MIN_SEEDING_SECS" ]; then
            PROTECTED_REASON="new ($(($SEEDING_TIME / 3600))h < $(($MIN_SEEDING_SECS / 3600))h)"
          fi

          # Protect if ratio is too low (unless aggressive mode)
          if [ -z "$PROTECTED_REASON" ] && [ "$AGGRESSIVE_MODE" = "false" ]; then
            if [ "$(echo "$RATIO < $MIN_RATIO" | bc -l)" -eq 1 ]; then
              PROTECTED_REASON="low ratio ($RATIO < $MIN_RATIO)"
            fi
          fi

          # Protect high-demand torrents (many leechers, few seeders)
          if [ -z "$PROTECTED_REASON" ] && [ "$KEEP_HIGH_DEMAND" = "true" ]; then
            # High demand = leecher/seeder ratio > 2
            if [ "$(echo "$DEMAND_RATIO > 2" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
              PROTECTED_REASON="high demand (L/S=$DEMAND_RATIO)"
            fi
          fi

          if [ -n "$PROTECTED_REASON" ]; then
            echo "🛡️  Protected: $NAME - $PROTECTED_REASON"
            PROTECTED=$((PROTECTED + 1))
            continue
          fi

          # ─────────────────────────────────────────────────────────
          # Deletion checks
          # ─────────────────────────────────────────────────────────
          DELETE_REASON=""

          # Check for slow upload speed over extended time
          if [ "$SEEDING_TIME" -ge "$SLOW_SEEDING_SECS" ]; then
            if [ "$UPSPEED" -lt "$MIN_UPLOAD_SPEED" ]; then
              DELETE_REASON="slow upload ($UPSPEED B/s < $MIN_UPLOAD_SPEED B/s for $(($SEEDING_TIME / 3600))h)"
            fi
          fi

          # In aggressive mode, also delete old high-ratio torrents
          if [ -z "$DELETE_REASON" ] && [ "$AGGRESSIVE_MODE" = "true" ]; then
            if [ "$(echo "$RATIO > 2.0" | bc -l)" -eq 1 ] && [ "$SEEDING_TIME" -gt "$MIN_SEEDING_SECS" ]; then
              DELETE_REASON="aggressive cleanup (ratio=$RATIO, disk=$DISK_USAGE%)"
            fi
          fi

          if [ -n "$DELETE_REASON" ]; then
            echo "🗑️  Deleting: $NAME - $DELETE_REASON"
            curl -sf -X POST "$QBIT_URL/api/v2/torrents/delete" \
              -d "hashes=$HASH" \
              -d "deleteFiles=true" || echo "Failed to delete $HASH"
            DELETED=$((DELETED + 1))
          fi
        done

        echo "───────────────────────────────────────────────────────────"
        echo "Summary: Deleted $DELETED, Protected $PROTECTED torrents"
        echo "═══════════════════════════════════════════════════════════"
      '';
    };
  };

  # ═══════════════════════════════════════════════════════════════
  # Cross-seed - Auto cross-seeding between PT sites
  # ═══════════════════════════════════════════════════════════════
  # Cross-seed uses Prowlarr's Torznab API to search for matching torrents
  # on other sites. The API key is read from sops at runtime.
  environment.etc."cross-seed/config.js" = mkIf cross-seed {
    text = ''
      module.exports = {
        // ─────────────────────────────────────────────────────────
        // qBittorrent Connection
        // ─────────────────────────────────────────────────────────
        qbittorrentUrl: "http://127.0.0.1:8080",

        // ─────────────────────────────────────────────────────────
        // Torznab Indexers (Prowlarr provides these)
        // Format: http://127.0.0.1:9696/prowlarr/{id}/api?apikey={key}
        // The URLs are constructed at runtime from Prowlarr API
        // ─────────────────────────────────────────────────────────
        torznab: [],  // Populated by cross-seed-update service

        // ─────────────────────────────────────────────────────────
        // Matching Strategy
        // ─────────────────────────────────────────────────────────
        action: "inject",      // Inject directly into qBittorrent
        matchMode: "safe",     // Conservative matching (recommended for PT)
        skipRecheck: false,    // Always verify data integrity
        linkType: "hardlink",  // Use hardlinks to save disk space
        linkDir: "/data/downloads/torrents/cross-seed",

        // ─────────────────────────────────────────────────────────
        // Paths
        // ─────────────────────────────────────────────────────────
        torrentDir: "/var/lib/qBittorrent/qBittorrent/BT_backup",
        dataDirs: [
          "/data/media",
          "/data/downloads/torrents"
        ],
        outputDir: "/data/downloads/torrents/cross-seed",

        // ─────────────────────────────────────────────────────────
        // Timing - Balance between catching seeds and API limits
        // ─────────────────────────────────────────────────────────
        rssCadence: "30 minutes",    // Check RSS every 30 min
        searchCadence: "1 day",      // Full search once daily
        snatchTimeout: "30 seconds",
        searchTimeout: "2 minutes",
        searchLimit: 100,            // Limit searches per run

        // ─────────────────────────────────────────────────────────
        // Logging
        // ─────────────────────────────────────────────────────────
        logLevel: "info",
      };
    '';
    user = "qbittorrent";
    group = "media";
    mode = "0640";
  };

  # Cross-seed directories
  systemd.tmpfiles.settings."cross-seed" = mkIf cross-seed {
    "/data/downloads/torrents/cross-seed".d = {
      user = "qbittorrent";
      group = "media";
      mode = "0775";
    };
    "/var/lib/cross-seed".d = {
      user = "qbittorrent";
      group = "media";
      mode = "0750";
    };
  };

  # ═══════════════════════════════════════════════════════════════
  # IYUU Plus - User and Configuration
  # ═══════════════════════════════════════════════════════════════
  users.users.iyuu = mkIf iyuu {
    isSystemUser = true;
    group = "media";
    home = "/var/lib/iyuu";
    createHome = true;
  };

  systemd.tmpfiles.settings."10-iyuu" = mkIf iyuu {
    "/var/lib/iyuu".d = {
      user = "iyuu";
      group = "media";
      mode = "0750";
    };
  };

  # SOPS template for IYUU .env file
  sops.templates."iyuu-env" = mkIf iyuu {
    content = ''
      APP_DEBUG=false
      APP_ENV=prod
      # IYUU_TOKEN=REPLACE_ME_IN_SOPS_OR_MANUALLY
      SERVER_LISTEN_PORT=${toString config.ports.iyuu}
      DB_CONNECTION=mysql
      DB_HOST=mysql.mag
      DB_PORT=${toString config.ports.mysql}
      DB_DATABASE=iyuu
      DB_USERNAME=iyuu
      DB_PASSWORD=
    '';
    owner = "iyuu";
    group = "media";
  };

  # ═══════════════════════════════════════════════════════════════
  # Vertex - Primary PT Tool
  # ═══════════════════════════════════════════════════════════════
  virtualisation.oci-containers.containers.vertex = mkIf vertex {
    image = "lswl/vertex:latest";
    extraOptions = [ "--network=host" ];
    volumes = [
      "/data/.state/vertex:/vertex/data"
      "/data/downloads/torrents:/data/downloads/torrents"
    ];
    environment = {
      TZ = "Asia/Shanghai";
      PORT = toString config.ports.vertex;
    };
  };

  # ═══════════════════════════════════════════════════════════════
  # Autobrr - Auto Racing for PT Sites
  # ═══════════════════════════════════════════════════════════════
  # Strategy: Monitor RSS feeds for FREE torrents and grab immediately
  #
  # Typical PT racing workflow:
  # 1. New torrent released on PT site
  # 2. Autobrr detects via RSS (delay ~1-5 min)
  # 3. If FREE tag present → grab immediately
  # 4. qBittorrent downloads and seeds
  # 5. Cross-seed finds matches on other sites
  # 6. More upload credit earned!
  #
  # Tips for efficient racing:
  # - Set reasonable size limits (e.g., 1GB-50GB)
  # - Filter by category (Movies, TV, etc.)
  # - Avoid HR (Hit and Run) torrents if ratio is low
  # - Keep seeding! Most PT sites reward long-term seeding
  #
  services.autobrr = mkIf autobrr {
    enable = true;
    secretFile = config.sops.secrets."autobrr/secret".path;
  };

  # Timer for smart torrent management
  systemd.timers.qbit-smart-manage = mkIf (qbittorrent && smartTorrentManagement) {
    description = "Run smart torrent management periodically";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "${toString smartConfig.cleanupIntervalMinutes}min";
      Persistent = true;
    };
  };
}
