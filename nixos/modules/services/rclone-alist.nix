{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.services.myRcloneMounts;
in
{
  options.services.myRcloneMounts = mkOption {
    type = types.attrsOf (
      types.submodule {
        options = {
          remotePath = mkOption {
            type = types.str;
            example = "alist:/onedrive/Sync/obsidian";
          };
          localPath = mkOption {
            type = types.str;
            example = "/var/lib/obsidian/data";
          };
        };
      }
    );
    default = { };
    description = "声明式定义 rclone 挂载映射";
  };

  config = mkIf (cfg != { }) {
    programs.fuse.userAllowOther = true;

    # 自动创建本地目录
    systemd.tmpfiles.rules = mapAttrsToList (_name: m: "d ${m.localPath} 0755 youruser users -") cfg;

    # 动态生成 systemd 服务
    systemd.services = mapAttrs' (
      name: m:
      nameValuePair "rclone-mount-${name}" {
        description = "Rclone mount for ${name}";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = ''
            ${pkgs.rclone}/bin/rclone mount ${m.remotePath} ${m.localPath} \
              --config=${config.sops.templates."mount-alist".path} \
              --vfs-cache-mode full \
              --vfs-cache-max-size 100G \
              --vfs-read-ahead 512M \
              --buffer-size 128M \
              --allow-other \
          '';
          ExecStop = "${pkgs.fuse}/bin/fusermount -uz ${m.localPath}";
          Restart = "on-failure";
          RestartSec = "10s";
        };
      }
    ) cfg;
    sops.templates."mount-alist" = {
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
  };
}
