{
  config,
  pkgs,
  ...
}:
let
  domain = config.networking.domain or "dora.im";
  baseUrl = "https://alist.${domain}/dav/onedrive";
  papersMountPoint = "/home/tippy/Storage/Papers";

  rcloneConfig = config.sops.templates."rclone-papers.conf".path;

in
{
  sops.secrets = {
    "alist/app/username".owner = "tippy";
    "alist/app/password-rclone".owner = "tippy";
  };
  sops.templates."rclone-papers.conf" = {
    owner = "tippy";
    mode = "0400";
    content = ''
      [papers-remote]
      type = webdav
      url = ${baseUrl}/Papers
      vendor = other
      user = ${config.sops.placeholder."alist/app/username"}
      pass = ${config.sops.placeholder."alist/app/password-rclone"}
    '';
  };

  environment.systemPackages = [
    pkgs.rclone
    pkgs.fuse3
  ];

  systemd.tmpfiles.rules = [
    "d ${papersMountPoint} 0755 tippy users -"
  ];

  # Root cannot access the user-owned FUSE mount; keep boot creation unchanged.
  systemd.services.systemd-tmpfiles-clean.serviceConfig.ExecStart = [
    ""
    "${config.systemd.package}/bin/systemd-tmpfiles --clean --exclude-prefix=${papersMountPoint}"
  ];

  # 登录时自动挂载 FUSE 挂载点，无需手动执行任何命令
  # 关键点：不使用 --vfs-refresh，挂载时完全不发起网络请求；
  # 只有当您真正打开或访问 Papers 目录时，rclone 才会按需向远端发起 WebDAV 网络请求。
  systemd.user.services.storage-papers = {
    description = "按需 WebDAV 挂载 Papers 论文库 (Rclone)";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = "tippy";
    startLimitIntervalSec = 0;
    path = [
      "/run/wrappers"
    ]
    ++ (with pkgs; [
      coreutils
      rclone
      fuse3
    ]);
    serviceConfig = {
      Type = "simple";
      ExecStartPre = pkgs.writeShellScript "pre-mount-papers" ''
        mkdir -p "${papersMountPoint}"
        /run/wrappers/bin/fusermount3 -u "${papersMountPoint}" 2>/dev/null || true
      '';
      ExecStart = pkgs.writeShellScript "start-mount-papers" ''
        # 启动挂载：移除 --vfs-refresh，实现真正的懒加载（进入目录时才请求网络）
        exec ${pkgs.rclone}/bin/rclone mount papers-remote: "${papersMountPoint}" \
          --config="${rcloneConfig}" \
          --vfs-cache-mode=full \
          --vfs-cache-max-size=5G \
          --vfs-cache-max-age=24h \
          --vfs-cache-poll-interval=1m \
          --vfs-read-chunk-size=16M \
          --vfs-read-chunk-size-limit=64M \
          --buffer-size=32M \
          --dir-cache-time=24h \
          --attr-timeout=1h \
          --no-modtime \
          --contimeout=5s \
          --timeout=15s \
          --retries=1 \
          --low-level-retries=2 \
          --no-checksum
      '';
      ExecStop = "/run/wrappers/bin/fusermount3 -u ${papersMountPoint}";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
