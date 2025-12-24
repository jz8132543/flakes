# file: ./rclone-executor.nix
{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.services.genericCloudSync;
  # 统一存储 Rclone 的状态数据（数据库、缓存）
  # 放在 /var/lib/syncthing 下是为了方便 NixOS 持久化管理
  rcloneHome = "/var/lib/syncthing";
  rcloneCacheDir = "${rcloneHome}/.cache/rclone";

  # 声明系统级过滤文件路径
  filterPath = "/etc/rclone-filters.txt";
in
{
  # --- 1. 扩展配置接口 (Options) ---
  options.services.genericCloudSync = {
    enable = mkEnableOption "通用云端 Bisync 同步服务";
    user = mkOption {
      type = types.str;
      default = "syncthing";
      description = "运行同步任务的用户";
    };
    tasks = mkOption {
      default = { };
      type = types.attrsOf (
        types.submodule {
          options = {
            localPath = mkOption { type = types.path; };
            remotePath = mkOption { type = types.str; };
            realtime = mkOption {
              type = types.bool;
              default = true;
            };
          };
        }
      );
    };
  };

  config = mkIf cfg.enable {

    # --- 2. 声明式系统配置文件 (environment.etc) ---
    environment.etc."rclone-filters.txt".text = ''
      - .stfolder/**
      - .DS_Store
      - Thumbs.db
      - desktop.ini
    '';

    # --- 3. 密钥与认证管理 (Sops-nix) ---
    sops.secrets = {
      "alist/app/username" = {
        owner = cfg.user;
      };
      "alist/app/password-rclone" = {
        owner = cfg.user;
      };
    };

    sops.templates."rclone-config" = {
      owner = cfg.user;
      content = ''
        [alist]
        type = webdav
        url = https://alist.${config.networking.domain}/dav
        vendor = rclone
        user = ${config.sops.placeholder."alist/app/username"}
        pass = ${config.sops.placeholder."alist/app/password-rclone"}
      '';
    };

    # --- 4. 核心执行引擎 (Systemd Service) ---
    systemd.services.rclone-sync-engine = {
      description = "Universal Rclone Bisync Engine with Auto-Init";
      after = [
        "network-online.target"
        "sops-nix.service"
      ];
      wants = [ "network-online.target" ];

      environment = {
        RCLONE_CONFIG = config.sops.templates."rclone-config".path;
        RCLONE_CACHE_DIR = rcloneCacheDir;
      };

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;

        # 性能与调度优化 (针对 4核/8G)
        Nice = 15; # CPU 谦让
        IOSchedulingClass = "best-effort"; # IO 谦让
        IOSchedulingPriority = 7;
        MemoryMax = "2G"; # 防止内存泄漏影响系统

        ExecStartPre = mapAttrsToList (
          _name: task: "-${pkgs.rclone}/bin/rclone mkdir ${task.remotePath}"
        ) cfg.tasks;
        # 智能同步脚本：自动处理首次运行的 --resync
        ExecStart = pkgs.writeShellScript "rclone-sync-smart" (
          concatStringsSep "\n" (
            mapAttrsToList (name: task: ''
              echo "--- Checking task: ${name} ---"

              # 检查 bisync 数据库是否存在。通常位于缓存目录下的 bisync 子目录
              # 数据库文件名通常包含本地路径和远程路径的特征，我们通过查找任务名来匹配
              DB_EXISTS=$(find ${rcloneCacheDir}/bisync -name "*${name}*" 2>/dev/null | wc -l || echo 0)

              if [ "$DB_EXISTS" -eq "0" ]; then
                echo "[First Run] No database found for '${name}'. Initializing with --resync..."
                ${pkgs.rclone}/bin/rclone bisync "${task.localPath}" "${task.remotePath}" \
                  --filter-from ${filterPath} \
                  --resync --force \
                  --transfers 2 --checkers 4 --use-mmap --quiet
              else
                echo "[Routine] Running incremental bisync for '${name}'..."
                ${pkgs.rclone}/bin/rclone bisync "${task.localPath}" "${task.remotePath}" \
                  --filter-from ${filterPath} \
                  --resync-mode newer --force \
                  --transfers 2 --checkers 4 --use-mmap --tpslimit 5 --quiet
              fi
            '') cfg.tasks
          )
        );
      };
    };

    # --- 5. 实时监听触发器 (Systemd Path) ---
    # 利用内核 inotify，仅在文件变动时触发同步，开销极低
    systemd.paths.rclone-sync-watcher = {
      description = "Real-time Watcher for rclone sync paths";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        # 监听所有注册了 realtime=true 的本地路径
        PathChanged = mapAttrsToList (_name: task: task.localPath) (
          filterAttrs (_n: t: t.realtime) cfg.tasks
        );
        # 防抖处理：变动后等待 60 秒触发，避免频繁保存导致的 CPU 激增
        TriggerLimitIntervalSec = "60s";
      };
    };
  };
}
