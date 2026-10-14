{
  config,
  pkgs,
  ...
}:
let
  domain = config.networking.domain or "dora.im";
  baseUrl = "https://alist.${domain}/dav/onedrive";
  papersMountPoint = "/home/tippy/Storage/Papers";

  rcloneConfig = pkgs.writeText "rclone-papers.conf" ''
    [papers-remote]
    type = webdav
    url = ${baseUrl}/Papers
    vendor = other
    user = dav
  '';

  mountPapers = pkgs.writeShellScriptBin "mount.papers" ''
    set -e
    TARGET=""
    for arg in "$@"; do
      if [ -d "$arg" ]; then
        TARGET="$arg"
      fi
    done
    if [ -z "$TARGET" ]; then
      TARGET="${papersMountPoint}"
    fi

    # Ensure target directory exists
    mkdir -p "$TARGET"

    PASSWORD=""
    PASSWORD_FILE="${config.sops.secrets."password".path}"
    if [ -f "$PASSWORD_FILE" ]; then
      PASSWORD="$(cat "$PASSWORD_FILE")"
      export RCLONE_CONFIG_PAPERS_REMOTE_PASS="$(${pkgs.rclone}/bin/rclone obscure "$PASSWORD")"
    fi

    exec ${pkgs.rclone}/bin/rclone mount papers-remote: "$TARGET" \
      --config="${rcloneConfig}" \
      --daemon \
      --allow-other \
      --uid=1000 \
      --gid=100 \
      --umask=022 \
      --vfs-cache-mode=full \
      --vfs-cache-max-size=5G \
      --vfs-cache-max-age=24h \
      --vfs-cache-poll-interval=1m \
      --vfs-read-chunk-size=16M \
      --vfs-read-chunk-size-limit=64M \
      --buffer-size=32M \
      --dir-cache-time=24h \
      --attr-timeout=1h \
      --vfs-refresh \
      --no-modtime \
      --contimeout=15s \
      --timeout=30s \
      --retries=2 \
      --low-level-retries=3 \
      --no-checksum
  '';
in
{
  sops.secrets."password" = { };

  environment.systemPackages = [
    mountPapers
    pkgs.rclone
  ];

  systemd.tmpfiles.rules = [
    "d ${papersMountPoint} 0755 tippy users -"
  ];

  fileSystems."${papersMountPoint}" = {
    device = "papers-remote:";
    fsType = "papers";
    options = [
      "nofail"
      "_netdev"
      "x-systemd.automount"
      "x-systemd.idle-timeout=10m"
      "x-systemd.device-timeout=5s"
    ];
  };
}
