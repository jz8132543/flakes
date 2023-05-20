{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (config.networking) hostName;
  defaultTimerConfig = {
    OnCalendar = "03:00:00";
    RandomizedDelaySec = "30min";
  };
  cfgB2 = {
    repository = "b2:doraim-backup-${hostName}";
    environmentFile = config.sops.templates."restic-b2-env".path;
    passwordFile = config.sops.secrets."restic_password".path;
    pruneOpts = [
      "--keep-daily 3"
      "--keep-weekly 2"
    ];
  };

  mkScript = cfg:
    pkgs.substituteAll ({
        src = ./wrapper.sh;
        isExecutable = true;
        inherit (pkgs) restic;
      }
      // cfg);
  mkServiceCfg = cfg:
    {
      initialize = true;
      timerConfig = lib.mkDefault defaultTimerConfig;
    }
    // cfg;

  scripts = pkgs.stdenvNoCC.mkDerivation {
    name = "restic-scripts";
    buildCommand = ''
      install -Dm755 $resticB2    $out/bin/restic-b2
    '';
    resticB2 = mkScript cfgB2;
  };
in {
  config = {
    services.restic.backups.b2 = mkServiceCfg cfgB2;

    sops.templates."restic-b2-env".content = ''
      B2_ACCOUNT_ID="${config.sops.placeholder."b2_backup_key_id"}"
      B2_ACCOUNT_KEY="${config.sops.placeholder."b2_backup_access_key"}"
    '';
    sops.secrets."restic_password" = {
      sopsFile = config.sops-file.terraform;
      restartUnits = ["restic-backups-b2.service" "restic-backups-minio.service"];
    };
    sops.secrets."b2_backup_key_id" = {
      sopsFile = config.sops-file.terraform;
      restartUnits = ["restic-backups-b2.service"];
    };
    sops.secrets."b2_backup_access_key" = {
      sopsFile = config.sops-file.terraform;
      restartUnits = ["restic-backups-b2.service"];
    };

    environment.systemPackages = [
      scripts
    ];
  };
}
