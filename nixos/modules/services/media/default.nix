# Media Stack - Based on Misterio77/nix-config
# https://github.com/Misterio77/nix-config/tree/main/hosts/merope/services/media
#
# This is a complete home theater automation stack with:
# - Jellyfin: Media server
# - Sonarr: TV series management
# - Radarr: Movie management
# - Prowlarr: Indexer management
# - Bazarr: Subtitle management
# - Jellyseerr: Request management
# - qBittorrent: Torrent client
# - FlareSolverr: Cloudflare bypass
#
# Auto-configuration modules set up all services with:
# - Username: i
# - Password: from sops secret "password"
# - Email: noreply@dora.im
# - SMTP Password: from sops secret "smtp/password"
{
  imports = [
    # Core home theater automation
    ./home-theater.nix

    # Media services
    ./jellyfin.nix
    ./sonarr.nix
    ./radarr.nix
    ./bazarr.nix
    ./prowlarr.nix
    ./jellyseerr.nix
    ./qbittorrent.nix
    ./flaresolverr.nix

    # Auto-configuration modules (one-time setup)
    ./jellyfin-auto-config.nix
    ./sonarr-auto-config.nix
    ./radarr-auto-config.nix
    ./prowlarr-auto-config.nix
    ./bazarr-auto-config.nix
    ./jellyseerr-auto-config.nix
    ./qbittorrent-auto-config.nix
  ];

  # Enable home theater automation by default
  services.homeTheater.enable = true;
}
