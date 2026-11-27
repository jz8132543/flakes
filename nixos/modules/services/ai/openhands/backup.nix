{ config, lib, ... }:
let
  cfg = config.services.ai.openhands;
in
{
  config = lib.mkIf cfg.enable {
    services.restic.backups.borgbase = {
      paths = lib.mkAfter [
        "${cfg.dataDir}/state"
        "${cfg.dataDir}/knowledge"
        cfg.skillsDir
        "${cfg.dataDir}/outputs"
        "${cfg.dataDir}/workspace"
      ];
      exclude = lib.mkAfter [
        "${cfg.dataDir}/state/cache/**"
        "${cfg.dataDir}/state/logs/**"
        "${cfg.dataDir}/workspace/**/.cache/**"
        "${cfg.dataDir}/workspace/**/node_modules/**"
        "${cfg.dataDir}/workspace/**/__pycache__/**"
        "${cfg.dataDir}/workspace/**/.venv/**"
      ];
    };
  };
}
