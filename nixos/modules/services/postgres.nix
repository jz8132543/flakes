{
  config,
  pkgs,
  ...
}: {
  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    package = pkgs.postgresql_15;
    extraPlugins = with pkgs; [
      postgresql15Packages.repmgr
      pgpool
      pgbouncer
    ];
    authentication = ''
      local all all trust
      host all all 100.64.0.0/10 trust
      host all all fdef:6567:bd7a::/48 trust
    '';
    settings = {
      # shared_preload_libraries = "repmgr";
    };
  };

  # backup postgresql database
  # services.postgresqlBackup = {
  #   enable = true;
  #   backupAll = true;
  #   compression = "zstd";
  # };
  # services.restic.backups.b2 = {
  #   paths = [
  #     config.services.postgresqlBackup.location
  #   ];
  # };
  # systemd.services."restic-backups-b2" = {
  #   requires = ["postgresqlBackup.service"];
  #   after = ["postgresqlBackup.service"];
  # };
}
