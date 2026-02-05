{
  config,
  pkgs,
  lib,
  ...
}:
{
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
        MemoryWorkingSetLimit = 1024;
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
          EnableSuperSeeding = true;
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

  systemd.tmpfiles.rules = [
    "d /data/downloads/torrents 0755 qbittorrent media -"
    "d /data/downloads/torrents/.incomplete 0755 qbittorrent media -"
    "d /data/downloads/torrents/tv-sonarr 0755 qbittorrent media -"
    "d /data/downloads/torrents/movies-radarr 0755 qbittorrent media -"
    "d /data/downloads/torrents/music-lidarr 0755 qbittorrent media -"
    "d /data/downloads/torrents/prowlarr 0755 qbittorrent media -"
    "d /data/torrents 0755 qbittorrent media -"
    "d /data/torrents/downloading 0755 qbittorrent media -"
    "d /data/torrents/completed 0755 qbittorrent media -"
    "d /var/lib/qBittorrent 0755 qbittorrent media -"
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

  networking.hosts."127.0.0.1" = [ "qbittorrent" ];
}
