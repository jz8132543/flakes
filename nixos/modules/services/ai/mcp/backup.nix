# ─────────────────────────────────────────────────────────────────────────────
# services/ai/mcp/backup.nix
#
# IBM ContextForge 灾备配置
# ─────────────────────────────────────────────────────────────────────────────
{
  lib,
  ...
}:
{
  # ContextForge 数据 100% 存储于 PostgreSQL 中，由 services.postgresqlBackup 统一备份，无需备份本地空目录。

  systemd.services."restic-backups-borgbase" = {
    after = lib.mkAfter [
      "postgresqlBackup.service"
    ];
  };
}
