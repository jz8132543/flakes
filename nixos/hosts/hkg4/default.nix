{ nixosModules, lib, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      nixosModules.services.telegraf
      nixosModules.services.doraim
      nixosModules.services.derp
      # nixosModules.services.stun
      (import nixosModules.services.xray {
        needProxy = true;
        proxyHost = "nue0.dora.im";
      })
      # nixosModules.services.tuic
      nixosModules.services.searx
      # nixosModules.services.perplexica
      nixosModules.services.rustdesk
      nixosModules.services.murmur
      nixosModules.services.teamspeak
      (import nixosModules.services.nixflix {
        # ══════════════════════════════════════════════════════════
        # PT Racing & Seeding Configuration
        # ══════════════════════════════════════════════════════════
        autobrr = true; # Auto-grab FREE torrents from RSS
        cross-seed = true; # Auto cross-seed between PT sites
        smartTorrentManagement = true; # Auto-delete slow seeders

        # Smart management tuning
        smartConfig = {
          minUploadSpeed = 1024; # 1 KB/s minimum before considered "slow"
          slowSeedingHours = 48; # Delete after 48h of slow upload
          minSeedingHours = 24; # Protect torrents for first 24h
          minRatio = 1.0; # Protect until 1.0 ratio achieved
          maxDiskUsagePercent = 90; # Aggressive cleanup when >90% full
          keepHighDemand = true; # Keep torrents with many leechers
          cleanupIntervalMinutes = 30; # Check every 30 min
        };

        # PT Site Indexers for Prowlarr
        prowlarrIndexers = [
          {
            name = "M-Team - TP";
            apiKey = {
              _secret = "/run/secrets/media/mteam_api_key";
            };
          }
          {
            name = "PTTime";
            apiKey = {
              _secret = "/run/secrets/media/pttime_api_key";
            };
          }
        ];
      })
      # nixosModules.media.jellyfin
      # nixosModules.services.headscale
      # (import nixosModules.services.alist { })
    ];
  nix.gc.options = lib.mkForce "-d";

  # ═══════════════════════════════════════════════════════════════
  # Firewall - Open qBittorrent listening port for PT
  # ═══════════════════════════════════════════════════════════════
  # Port 51413 is essential for incoming peer connections
  # Without it, you can only connect to peers, not receive connections
  # This significantly reduces upload potential!
  networking.firewall = {
    allowedTCPPorts = [
      8081
      51413
    ]; # 51413 = qBittorrent
    allowedUDPPorts = [ 51413 ]; # For uTP protocol
  };
}
