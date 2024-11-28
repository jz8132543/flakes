{ config, pkgs, ... }:
let
  portNumber = 8096;
in
{
  services.jellyfin.enable = true;
  users.users.jellyfin.extraGroups = [ "media" ];

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      jellyfin = {
        rule = "Host(`jellyfin.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "jellyfin";
      };
    };
    services = {
      jellyfin.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString portNumber}"; } ];
      };
    };
  };
  # systemd.tmpfiles.rules = [
  #   # "d '/mnt/alist' 0077 jellyfin jellyfin - -"
  #   "d '/mnt/jellyfin/alist' 0777 jellyfin jellyfin - -"
  #   "d '/var/empty/.cache/rclone/' 0775 root root - -"
  # ];
  systemd.services.mount-alist = {
    after = [ "network-online.target" ];
    serviceConfig = {
      User = "root";
      Type = "notify";
      Restart = "on-failure";
      # ExecStartPre = "/usr/bin/env mkdir -p /var/cache/jellyfin/mount-alist";
      ExecStart = ''
        ${pkgs.rclone}/bin/rclone \
        --config=${config.sops.templates."mount-alist".path} \
        --use-mmap \
        --allow-non-empty \
        --vfs-cache-mode=full \
        --vfs-cache-max-age=1h \
        --vfs-cache-max-size=5G \
        --buffer-size=16M \
        --dir-cache-time=5m \
        --poll-interval=1m \
        --vfs-read-ahead=128M \
        --network-mode \
        --tpslimit=10 \
        --tpslimit-burst=10 \
        --transfers=4 \
        --vfs-read-chunk-size=5M \
        --vfs-read-chunk-size-limit=50M \
        --log-file=/var/log/rclone.log \
        --allow-other=true \
        --header=Referer: \
        mount alist: /mnt/alist -vv
      '';
      ExecStop = "/run/wrappers/bin/fusermount -u /mnt/alist";
    };
    wantedBy = [ "default.target" ];
  };
  sops.templates."mount-alist" = {
    owner = "jellyfin";
    content = ''
      [alist]
      type = webdav
      url = https://alist.${config.networking.domain}/dav
      vendor = rclone
      user = ${config.sops.placeholder."alist/app/username"}
      pass = ${config.sops.placeholder."alist/app/password-rclone"}
    '';
  };
  sops.secrets = {
    "alist/app/username" = { };
    "alist/app/password-rclone" = { };
  };
  systemd.packages = with pkgs; [ rclone ];
}
