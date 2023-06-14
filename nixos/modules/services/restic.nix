{
  config,
  lib,
  ...
}: {
  config = {
    services.restic.backups.borgbase = {
      initialize = true;
      timerConfig = lib.mkDefault {
        OnCalendar = "03:00:00";
        RandomizedDelaySec = "30min";
      };
      passwordFile = config.sops.secrets."restic/password".path;
      repositoryFile = config.sops.secrets."restic/borgbase".path;
      pruneOpts = [
        "--keep-daily 3"
        "--keep-weekly 2"
      ];
    };

    sops.secrets."restic/password" = {
      restartUnits = ["restic-backups-borgbase.service"];
    };
    sops.secrets."restic/borgbase" = {
      restartUnits = ["restic-backups-borgbase.service"];
    };
  };
}
