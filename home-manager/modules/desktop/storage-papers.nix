{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  domain = osConfig.networking.domain;
  # 统一 WebDAV 存储 Base URL：使用 baseUrl 变量，各组件独立划分子目录
  baseUrl = "https://alist.${domain}/dav/onedrive";
  papersMountPoint = "${config.home.homeDirectory}/Storage/Papers";
  rcloneConfig = config.sops.templates."rclone-papers-mount".path;
in
{
  sops.secrets = {
    "password" = { };
  };

  # 1. 生成 rclone 配置模板，指向统一存储底座下的 ${baseUrl}/Papers
  sops.templates."rclone-papers-mount" = {
    content = ''
      [papers-remote]
      type = webdav
      url = ${baseUrl}/Papers
      vendor = other
      user = dav
      pass = ${config.sops.placeholder."password"}
    '';
  };

  # 2. 声明式初始化本地挂载点目录
  home.activation.initPapersMountDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.coreutils}/bin/mkdir -p "${papersMountPoint}"
  '';

  # 3. 注册 systemd user 服务：按需缓存透明挂载 (VFS Cache Mode Full)
  systemd.user.services.mount-papers = {
    Unit = {
      Description = "Mount Remote Academic Papers (${baseUrl}/Papers) to Local Virtual POSIX Path";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Install = {
      WantedBy = [ "default.target" ];
    };

    Service = {
      Type = "simple";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${papersMountPoint}";
      ExecStart = ''
        ${pkgs.rclone}/bin/rclone mount papers-remote: ${papersMountPoint} \
          --config=${rcloneConfig} \
          --vfs-cache-mode=full \
          --vfs-cache-max-age=72h \
          --vfs-cache-max-size=10G \
          --vfs-read-chunk-size=32M \
          --buffer-size=64M \
          --dir-cache-time=1m \
          --no-modtime \
          --umask=022
      '';
      ExecStop = "${pkgs.fuse}/bin/fusermount -u ${papersMountPoint}";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
}
