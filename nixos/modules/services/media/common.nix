{
  lib,
  ...
}:
{
  config = {
    # Consolidated Systemd Configuration
    systemd.tmpfiles.rules = [
      "Z /data 0777 root media -"
      "Z /data/media 0777 root media -"
      "Z /data/downloads 0777 root media -"
      "Z /data/downloads/usenet 0777 sabnzbd media -"
      "Z /data/downloads/usenet/incomplete 0777 sabnzbd media -"
      "Z /data/downloads/usenet/complete 0777 sabnzbd media -"
      "Z /data/.state 0777 root media -"

      "Z /data/.state/jellyfin 0777 jellyfin media -"
      "Z /data/.state/jellyseerr 0777 jellyseerr media -"
      "Z /data/.state/sonarr 0777 sonarr media -"
      "Z /data/.state/sonarr-anime 0777 sonarr-anime media -"
      "Z /data/.state/radarr 0777 radarr media -"
      "Z /data/.state/prowlarr 0777 prowlarr media -"
      "Z /data/.state/lidarr 0777 lidarr media -"
      "Z /data/.state/sabnzbd 0777 sabnzbd media -"
      "Z /data/.state/recyclarr 0777 recyclarr media -"
      "Z /data/.state/autobrr 0777 autobrr media -"
      "Z /data/.state/vertex 0777 root media -"
      "Z /data/.state/iyuu 0777 root media -"
      "Z /var/lib/bazarr 0777 bazarr media -"

      "Z /var/lib/iyuu 0777 iyuu media -"
      "Z /var/lib/autobrr 0777 autobrr media -"
    ];

    # Other system settings (Boot, Networking, Users, SOPs, Containers)
    boot.kernel.sysctl = {
      "net.ipv4.tcp_max_orphans" = lib.mkDefault 65535;
      "net.ipv4.tcp_sack" = lib.mkDefault 1;
      "net.ipv4.tcp_timestamps" = lib.mkDefault 1;
      "net.core.optmem_max" = lib.mkDefault 65535;
      "fs.nr_open" = lib.mkDefault 2097152;
      "net.ipv4.tcp_mem" = lib.mkDefault "786432 1048576 134217728";
      "net.ipv4.udp_mem" = lib.mkDefault "786432 1048576 134217728";
    };

    networking.hosts."127.0.0.1" = [
      "sonarr"
      "radarr"
      "prowlarr"
      "lidarr"
      "sabnzbd"
      "bazarr"
      "qbittorrent"
    ];

    environment.global-persistence.directories = [
      "/data"
      "/var/lib/bazarr"
      "/data/.state/autobrr"
    ];

    # Shared SOBs Secrets definitions
    sops.secrets =
      let
        mkSecret = mode: name: { inherit mode; } // { inherit name; };
        mkArr =
          mode: names:
          builtins.listToAttrs (
            map (n: {
              name = n;
              value = mkSecret mode n;
            }) names
          );
      in
      mkArr "0444" [ "password" ]
      // mkArr "0400" [
        "media/sonarr_api_key"
        "media/radarr_api_key"
        "media/prowlarr_api_key"
        "media/jellyfin_api_key"
        "media/jellyseerr_api_key"
        "media/lidarr_api_key"
        "media/sabnzbd_api_key"
        "media/sabnzbd_nzb_key"
        "media/mteam_api_key"
        "media/pttime_api_key"
        "media/iyuu_token"
        "media/autobrr_session_token"
        "media/pttime_username"
        "media/mteam_rss_url"
        "media/pttime_rss_url"
        "media/moviepilot_api_key"
      ];
  };
}
