# Home Theater Automation Module
# This module provides one-click setup for a complete home theater system
# Username: i, Password: from sops "password" path
# Email: noreply@dora.im, SMTP Password: from sops "smtp/password" path
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.homeTheater;

  # Common credentials
in
{
  options.services.homeTheater = {
    enable = lib.mkEnableOption "home theater automation";

    domain = lib.mkOption {
      type = lib.types.str;
      default = config.networking.domain;
      description = "Domain for media services";
    };

    mediaDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/media";
      description = "Base directory for media files";
    };

    torrentsDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/torrents";
      description = "Base directory for torrent downloads";
    };
  };

  config = lib.mkIf cfg.enable {
    # Declare sops secrets for media services
    # Note: sops path uses dots in nix, which maps to nested yaml structure
    # e.g., "media/sonarr_api_key" in nix = media.sonarr_api_key in yaml = media:\n  sonarr_api_key: ...
    sops.secrets = {
      "password" = {
        mode = "0444";
      };
      "smtp/password" = {
        mode = "0400";
      };
      "media/sonarr_api_key" = {
        mode = "0400";
        owner = "sonarr";
      };
      "media/radarr_api_key" = {
        mode = "0400";
        owner = "radarr";
      };
      "media/prowlarr_api_key" = {
        mode = "0400";
        owner = "prowlarr";
      };
    };

    # Create media group for shared file access
    users.groups.media = { };

    # Create directory structure
    systemd.tmpfiles.settings = {
      "srv-media" = {
        "${cfg.mediaDir}".d = {
          user = "root";
          group = "media";
          mode = "0775";
        };
        "${cfg.mediaDir}/tv".d = {
          user = "sonarr";
          group = "media";
          mode = "0775";
        };
        "${cfg.mediaDir}/movies".d = {
          user = "radarr";
          group = "media";
          mode = "0775";
        };
        "${cfg.mediaDir}/music".d = {
          user = "root";
          group = "media";
          mode = "0775";
        };
      };

      "srv-torrents" = {
        "${cfg.torrentsDir}".d = {
          user = "qbittorrent";
          group = "media";
          mode = "0775";
        };
        "${cfg.torrentsDir}/downloading".d = {
          user = "qbittorrent";
          group = "media";
          mode = "0775";
        };
        "${cfg.torrentsDir}/completed".d = {
          user = "qbittorrent";
          group = "media";
          mode = "0775";
        };
        "${cfg.torrentsDir}/tv-sonarr".d = {
          user = "qbittorrent";
          group = "media";
          mode = "0775";
        };
        "${cfg.torrentsDir}/movies-radarr".d = {
          user = "qbittorrent";
          group = "media";
          mode = "0775";
        };
      };

      # Service data directories
      "var-lib-media" = {
        "/var/lib/jellyfin".d = {
          user = "jellyfin";
          group = "media";
          mode = "0750";
        };
        "/var/lib/jellyfin/data".d = {
          user = "jellyfin";
          group = "media";
          mode = "0750";
        };
        "/var/lib/jellyfin/config".d = {
          user = "jellyfin";
          group = "media";
          mode = "0750";
        };
        "/var/lib/jellyfin/log".d = {
          user = "jellyfin";
          group = "media";
          mode = "0750";
        };
        "/var/lib/jellyfin/cache".d = {
          user = "jellyfin";
          group = "media";
          mode = "0750";
        };
        "/var/lib/sonarr".d = {
          user = "sonarr";
          group = "media";
          mode = "0750";
        };
        "/var/lib/radarr".d = {
          user = "radarr";
          group = "media";
          mode = "0750";
        };
        "/var/lib/prowlarr".d = {
          user = "prowlarr";
          group = "media";
          mode = "0750";
        };
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
        "/var/lib/qbittorrent/.config".d = {
          user = "qbittorrent";
          group = "media";
          mode = "0750";
        };
        "/var/lib/qbittorrent/.config/qBittorrent".d = {
          user = "qbittorrent";
          group = "media";
          mode = "0750";
        };
        "/var/lib/jellyseerr".d = {
          user = "jellyseerr";
          group = "media";
          mode = "0750";
        };
      };
    };

    # Environment variables for automation scripts
    environment.systemPackages = with pkgs; [
      curl
      jq
      sqlite
      xmlstarlet
      python3
    ];
  };
}
