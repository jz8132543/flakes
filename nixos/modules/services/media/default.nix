# Media Stack - Based on Misterio77/nix-config
# https://github.com/Misterio77/nix-config/tree/main/hosts/merope/services/media
{
  imports = [
    ./jellyfin.nix
    ./sonarr.nix
    ./radarr.nix
    ./bazarr.nix
    ./prowlarr.nix
    ./jellyseerr.nix
    ./qbittorrent.nix
    ./flaresolverr.nix
  ];
}
