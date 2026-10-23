# ─────────────────────────────────────────────────────────────────────────────
# services/ai/companion/backup.nix
#
# AI 伴侣与 IM 机器人 5GB 极简灾备配置（Restic 严格排除多媒体缓存）
#
# 策略：
#   仅备份核心配置、SQL/SQLite 数据库与人设/知识库源文本，
#   严格排除 NapCat NTQQ 接收并下载的动辄数 GB 的群聊图片/音频/视频缓存文件，
#   确保单次快照体积压缩至 50MB 以内，从根本上防止撑爆 5GB 远程存储配额。
# ─────────────────────────────────────────────────────────────────────────────
{
  config,
  lib,
  ...
}:
let
  cfg = config.services.ai.companion;
in
{
  config = lib.mkIf cfg.enable {
    services.restic.backups.borgbase = {
      paths = lib.mkAfter (
        [
          "${cfg.dataDir}/personas"
          "${cfg.dataDir}/memory"
          "${cfg.wechat.dataDir}"
          "${cfg.matrix.dataDir}"
        ]
        ++ lib.optionals cfg.qq.enable [
          "${cfg.qq.dataDir}/napcat/config"
          "${cfg.qq.dataDir}/astrbot/data/cmd_config.json"
          "${cfg.qq.dataDir}/astrbot/data/data_v4.db"
        ]
      );

      exclude = lib.mkAfter [
        # ── 排除 NTQQ 多媒体下载缓存（群聊大文件垃圾）────────────────
        "**/napcat/data/**/ChatMsg/**"
        "**/napcat/data/**/Audio/**"
        "**/napcat/data/**/Video/**"
        "**/napcat/data/**/Pic/**"
        "**/napcat/data/**/OriPic/**"
        "**/napcat/data/**/Group/**"
        "**/napcat/data/**/Crashpad/**"
        "**/napcat/logs/**"

        # ── 排除 AstrBot 运行日志与临时文件夹 ─────────────────────────
        "${cfg.qq.dataDir}/astrbot/data/logs/**"
        "${cfg.qq.dataDir}/astrbot/data/temp/**"
        "${cfg.qq.dataDir}/astrbot/data/attachments/**"
        "${cfg.qq.dataDir}/astrbot/data/site-packages/**"

        # ── 排除通用临时文件 ──────────────────────────────────────────
        "**/cache/**"
        "**/Cache/**"
        "**/temp/**"
        "**/tmp/**"
        "**/__pycache__/**"
      ];
    };
  };
}
