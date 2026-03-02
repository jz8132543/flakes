{
  lib,
  config,
  ...
}:
{
  config = {
    # Consolidated Systemd Configuration
    systemd.tmpfiles.rules = [
      "Z /data 0777 root media -"
      "Z /data/media 0777 root media -"
      "Z /data/downloads 0777 root media -"
      # "Z /data/downloads/usenet 0777 sabnzbd media -"
      # "Z /data/downloads/usenet/incomplete 0777 sabnzbd media -"
      # "Z /data/downloads/usenet/complete 0777 sabnzbd media -"
      "Z /data/.state 0777 root media -"

      "Z /data/.state/jellyfin 0777 jellyfin media -"
      "Z /data/.state/jellyseerr 0777 jellyseerr media -"
      "Z /data/.state/sonarr 0777 sonarr media -"
      "Z /data/.state/sonarr-anime 0777 sonarr-anime media -"
      "Z /data/.state/radarr 0777 radarr media -"
      "Z /data/.state/prowlarr 0777 prowlarr media -"
      "Z /data/.state/lidarr 0777 lidarr media -"
      # "Z /data/.state/sabnzbd 0777 sabnzbd media -"
      "Z /data/.state/recyclarr 0777 recyclarr media -"
      "Z /data/.state/autobrr 0777 autobrr media -"
      "Z /data/.state/vertex 0777 root media -"
      "Z /data/.state/iyuu 0777 root media -"
      "d /data/.state/tdarr 0777 root media -"
      "d /data/.state/tdarr/server 0777 root media -"
      "d /data/.state/tdarr/configs 0777 root media -"
      "d /data/.state/tdarr/logs 0777 root media -"
      "d /data/.state/unmanic 0777 root media -"
      "d /tmp/tdarr-transcode 0777 root media -"
      "d /tmp/unmanic-transcode 0777 root media -"
      "Z /var/lib/bazarr 0777 bazarr media -"

      "Z /var/lib/iyuu 0777 iyuu media -"
      "Z /var/lib/autobrr 0777 autobrr media -"
    ];

    networking.hosts."127.0.0.1" = [
      "sonarr"
      "radarr"
      "prowlarr"
      "lidarr"
      # "sabnzbd"
      "bazarr"
      "qbittorrent"
    ];

    environment.global-persistence.directories = [
      "/var/lib/bazarr"
    ]
    ++ lib.optional (!builtins.hasAttr "/data" config.fileSystems) "/data";

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
        # "media/sabnzbd_api_key"
        # "media/sabnzbd_nzb_key"
        "media/mteam_api_key"
        "media/pttime_api_key"
        "media/iyuu_token"
        "media/autobrr_session_token"
        "media/pttime_username"
        "media/mteam_rss_url"
        "media/pttime_rss_url"
        "media/moviepilot_api_key"
        "jellyfin/oidc_client_secret"
      ];
  };
}
