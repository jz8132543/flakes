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
    '';
  };

  # 2. 声明式初始化本地挂载点目录
  home.activation.initPapersMountDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.coreutils}/bin/mkdir -p "${papersMountPoint}"
  '';

  # 3. 注册 systemd user 服务：按需流式缓存透明挂载 (VFS Cache Mode Full + 严格容量上限)
  systemd.user.services.mount-papers = {
    Unit = {
      Description = "Mount Remote Academic Papers (${baseUrl}/Papers) to Local Virtual POSIX Path (On-Demand Cache)";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Install = {
      WantedBy = [ "default.target" ];
    };

    Service = {
      Type = "simple";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${papersMountPoint}";
      ExecStart = toString (
        pkgs.writeShellScript "mount-papers-start" ''
          PASSWORD_FILE="${config.sops.secrets."password".path}"
          if [ -f "$PASSWORD_FILE" ]; then
            PASSWORD="$(cat "$PASSWORD_FILE")"
            export RCLONE_CONFIG_PAPERS_REMOTE_PASS="$(${pkgs.rclone}/bin/rclone obscure "$PASSWORD")"
          fi
          exec ${pkgs.rclone}/bin/rclone mount papers-remote: ${papersMountPoint} \
            --config=${rcloneConfig} \
            --vfs-cache-mode=full \
            --vfs-cache-max-size=5G \
            --vfs-cache-max-age=24h \
            --vfs-cache-poll-interval=1m \
            --vfs-read-chunk-size=16M \
            --vfs-read-chunk-size-limit=64M \
            --buffer-size=32M \
            --dir-cache-time=2m \
            --no-modtime \
            --umask=022
        ''
      );
      ExecStop = "${pkgs.fuse}/bin/fusermount -u ${papersMountPoint}";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
}
