{
  config,
  pkgs,
  lib,
  nixosModules,
  ...
}: {
  imports = [
    nixosModules.services.restic
  ];
  networking.firewall.allowedTCPPorts = [5432];
  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    package = pkgs.postgresql_15;
    logLinePrefix = "user=%u,db=%d,app=%a,client=%h ";
    authentication = lib.mkForce ''
      local all all                           trust
      host all all 127.0.0.1/32               trust
      host all all ::1/128                    trust
      host all all 100.64.0.0/10              trust
      host all all fd7a:115c:a1e0::/48        trust
      host replication all 100.64.0.0/10      trust
      host replication all fd7a:115c:a1e0::/48 trust
    '';
    settings = {
      password_encryption = "scram-sha-256";
      hot_standby = "on";
      wal_level = "logical";
      max_wal_senders = 10;
      max_replication_slots = 10;
      archive_mode = "on";
      archive_command = "/run/current-system/sw/bin/true";
      wal_log_hints = "on";
    };
  };

  # backup postgresql database
  services.postgresqlBackup = {
    enable = true;
    backupAll = true;
    compression = "zstd";
  };
  services.restic.backups.borgbase.paths = [
    config.services.postgresqlBackup.location
  ];
  systemd.services."restic-backups-borgbase" = {
    requires = ["postgresqlBackup.service"];
    after = ["postgresqlBackup.service"];
  };
}
