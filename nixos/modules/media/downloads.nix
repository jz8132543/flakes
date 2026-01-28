{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.services.media-downloads;
in
{
  options.services.media-downloads = {
    enable = mkEnableOption "Media Downloads (qBittorrent)";
  };

  config = mkIf cfg.enable {
    # qBittorrent
    # Warning: qbittorrent-nox service in NixOS might need specific firewall config
    services.qbittorrent = {
      enable = true;
      openFirewall = true;
      group = "media"; # Run with media group access
      user = "qbit";
    };

    # Ensure qbit user is in media group clearly
    users.users.qbit = {
      isSystemUser = true;
      group = "media";
      extraGroups = [ "media" ];
      createHome = true;
      home = "/var/lib/qbittorrent";
    };

    # Optional: Wire up to /var/lib/media/downloads if exists
    # But qbittorrent handles save paths internally via UI associated with config
  };
}
