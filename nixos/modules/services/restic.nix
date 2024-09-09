{
  config,
  lib,
  ...
}:
{
  config = {
    services.restic.backups.borgbase = {
      initialize = true;
      timerConfig = lib.mkDefault {
        OnCalendar = "03:00:00";
        RandomizedDelaySec = "30min";
      };
      passwordFile = config.sops.secrets."restic/RESTIC_PASSWORD".path;
      repositoryFile = config.sops.secrets."restic/RESTIC_REPOSITORY".path;
      pruneOpts = [
        "--keep-daily 3"
        "--keep-weekly 2"
      ];
    };

    sops.secrets."restic/RESTIC_PASSWORD" = {
      restartUnits = [ "restic-backups-borgbase.service" ];
    };
    sops.secrets."restic/RESTIC_REPOSITORY" = {
      restartUnits = [ "restic-backups-borgbase.service" ];
    };
  };
}
