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
      profileDir = "/var/lib/qbittorrent";
      webuiPort = config.ports.qbittorrent;
    };

    # Ensure qbit user is in media group clearly
    users.users.qbit = {
      isSystemUser = true;
      group = "media";
      extraGroups = [ "media" ];
      createHome = true;
      home = "/var/lib/qbittorrent";
    };

    # Set default save path via systemd service environment or ensure user configures it manually in UI.
    # We encourage using /var/lib/data/torrents
    systemd.tmpfiles.rules = [
      "d /var/lib/qbittorrent 0770 qbit media - -"
    ];

    services.traefik.dynamicConfigOptions.http = {
      routers.qbittorrent = {
        rule = "Host(`qbit.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "qbittorrent";
        # middlewares = [ "auth" ];
      };
      services.qbittorrent.loadBalancer.servers = [
        { url = "http://localhost:${toString config.ports.qbittorrent}"; }
      ];
    };
  };
}
