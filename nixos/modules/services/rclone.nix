{
  config,
  pkgs,
  lib,
  ...
}:
let
  preScript =
    let
      app = pkgs.writeShellApplication {
        name = "preScript";
        runtimeInputs = with pkgs; [
          coreutils
          util-linux
        ];
        text = ''
          # /run/wrappers/bin/fusermount -u /mnt/alist || true
          umount /mnt/alist || true
          /usr/bin/env mkdir -p /mnt/alist || true
          exit 0
        '';
      };
    in
    lib.getExe app;
in
{
  systemd.services.mount-alist = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      User = "root";
      Type = "notify";
      Restart = "on-failure";
      ExecStartPre = preScript;
      ExecStart = ''
        ${pkgs.rclone}/bin/rclone \
        --config=${config.sops.templates."mount-alist".path} \
        --use-mmap \
        --allow-other \
        --vfs-cache-mode=full \
        --vfs-cache-max-age=1h \
        --vfs-cache-max-size=5G \
        --buffer-size=32M \
        --dir-cache-time=5m \
        --poll-interval=1m \
        --vfs-read-ahead=128M \
        --network-mode \
        --tpslimit=10 \
        --tpslimit-burst=10 \
        --transfers=4 \
        --vfs-read-chunk-size=16M \
        --vfs-read-chunk-size-limit=64M \
        --log-file=/var/log/rclone.log \
        --header=Referer: \
        --umask 000 \
        mount alist: /mnt/alist -vv
      '';
      ExecStop = "${pkgs.fuse}/bin/fusermount -u /mnt/alist || true";
    };
    wantedBy = [ "multi-user.target" ];
  };
  sops.templates."mount-alist" = {
    # owner = "jellyfin";
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
