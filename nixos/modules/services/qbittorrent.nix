{
  config,
  pkgs,
  lib,
  ...
}:
{
  users.users.qbittorrent = {
    group = "media";
    uid = config.ids.uids.qbittorrent;
    isSystemUser = true;
  };
  users.groups.qbittorrent.gid = config.ids.gids.qbittorrent;

  services.qbittorrent = {
    enable = true;
    # package = pkgs.qbittorrent-enhanced-nox;
    group = "media";
    webuiPort = config.ports.qbittorrent;
    serverConfig = {
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
          DefaultSavePath = "/data/downloads/torrents";
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
          ChokingAlgorithm = "FastestUpload";
          SeedChokingAlgorithm = "AntiLeech";
          UploadSlotsBehavior = "UploadRateBased";
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
        ExternalProgramEnabled = config.environment.seedbox.enable;
        ExternalProgramOnTorrentAdded = lib.mkIf config.environment.seedbox.enable "${pkgs.curl}/bin/curl -s -X POST \"http://localhost:${toString config.ports.qbittorrent}/api/v2/torrents/setUploadLimit\" -d \"hashes=%I&limit=10485760\"";
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
          ProxyType = if config.environment.seedbox.enable then 2 else 0; # 2 = SOCKS5, 0 = None
          ProxyIP = if config.environment.seedbox.enable then config.environment.seedbox.proxyHost else "";
          ProxyPort =
            if config.environment.seedbox.enable then config.environment.seedbox.proxyPort else 8080;
          ProxyPeerConnections = false;
          ProxyTrackerConnections = true;
          ProxyUDP = false;
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

  # ═══════════════════════════════════════════════════════════════
  # PT Whitening - Automated IP Reporting
  # ═══════════════════════════════════════════════════════════════
  systemd.services.qbit-ip-reporter = lib.mkIf config.environment.seedbox.enable {
    description = "Report qBittorrent public IP to tracker";
    after = [ "qbittorrent.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart =
        let
          script = pkgs.writeShellScript "qbit-ip-reporter.sh" ''
            # Get current public IP
            CURRENT_IP=$(${pkgs.curl}/bin/curl -s https://api.ipify.org)
            if [ -z "$CURRENT_IP" ]; then
              echo "Failed to get public IP"
              exit 1
            fi
            echo "Reporting public IP: $CURRENT_IP"

            # Use WebAPI to set AnnounceIP
            # No auth needed for localhost as per config.Preferences.WebUI.LocalHostAuth = false
            ${pkgs.curl}/bin/curl -i -X POST "http://localhost:${toString config.ports.qbittorrent}/api/v2/app/setPreferences" \
              -d "json={\"announce_ip\":\"$CURRENT_IP\"}"
          '';
        in
        "${script}";
      User = "qbittorrent";
    };
  };

  systemd.timers.qbit-ip-reporter = lib.mkIf config.environment.seedbox.enable {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "10min";
    };
  };

  systemd.tmpfiles.rules = [
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

  systemd.services.qbittorrent.serviceConfig = {
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
    UMask = "0002";
  };

  environment.global-persistence.directories = [
    "/var/lib/qbittorrent"
  ];

  networking.firewall = {
    allowedTCPPorts = [ 51413 ]; # qBittorrent
    allowedUDPPorts = [ 51413 ]; # uTP protocol
  };
  networking.hosts."127.0.0.1" = [ "qbittorrent" ];
}
