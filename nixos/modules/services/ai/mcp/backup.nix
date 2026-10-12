# ─────────────────────────────────────────────────────────────────────────────
# services/ai/mcp/backup.nix
#
# IBM ContextForge 灾备配置
# ─────────────────────────────────────────────────────────────────────────────
{
  config,
  lib,
  ...
}:
let
  cfg = config.services.ai.mcp;
in
{
  services.restic.backups.borgbase = {
    paths = lib.mkAfter [
      "${cfg.dataDir}/config"
      "${cfg.dataDir}/data"
    ];

    exclude = lib.mkAfter [
      "${cfg.dataDir}/logs"
    ];
  };

  systemd.services."restic-backups-borgbase" = {
    after = lib.mkAfter [
      "postgresqlBackup.service"
    ];
  };
}
