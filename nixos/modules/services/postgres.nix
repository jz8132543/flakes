{
  config,
  pkgs,
  self,
  ...
}: let
  repmgr = config.services.postgresql.package.pkgs.repmgr;
  repmgrConfig = ''
    node_id=${self.lib.data.hosts.${config.networking.hostName}.id}
    node_name='${config.networking.hostName}'
    conninfo='host=${config.networking.hostName}.ts.dora.im user=postgres dbname=repmgr connect_timeout=2'
    data_directory='${config.services.postgresql.dataDir}'
    repmgr_bindir='${repmgr}/bin'
    pg_bindir='${config.services.postgresql.package}/bin'
    replication_user='postgres'

    failover=automatic
    promote_command='${repmgr}/bin/repmgr standby promote -f /etc/repmgr.conf --log-to-file'
    follow_command='${repmgr}/bin/repmgr standby follow -f /etc/repmgr.conf --log-to-file --upstream-node-id=%n'

    service_start_command='sudo systemctl start postgresql.service'
    service_stop_command='sudo systemctl stop postgresql.service'
    service_restart_command'sudo systemctl restart postgresql.service'
    service_reload_command'sudo systemctl reload postgresql.service'
  '';
in {
  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    package = pkgs.postgresql_15;
    extraPlugins = with pkgs; [
      # postgresql15Packages.repmgr
      repmgr
      pgpool
      pgbouncer
    ];
    authentication = ''
      local all all trust
      host all all 100.64.0.0/10 trust
      host all all fdef:6567:bd7a::/48 trust
    '';
    settings = {
      password_encryption = "scram-sha-256";
      hot_standby = "on";
      wal_level = "replica";
      max_wal_senders = 10;
      max_replication_slots = 10;
      # wal_keep_segments = 30;
      archive_mode = "on";
      archive_command = "/run/current-system/sw/bin/true";
      # Required for repmgrd
      # shared_preload_libraries = "repmgr";
    };
    ensureDatabases = ["repmgr"];
  };

  systemd.sockets.repmgr_role = {
    socketConfig = {
      ListenStream = "${config.networking.hostName}.ts.dora.im:9999";
      Accept = true;
    };
    wantedBy = ["sockets.target"];
  };

  systemd.services."repmgr_role@" = {
    description = "Service for HAProxy to check node status/role";
    wants = ["repmgr-passwd-key.service"];
    serviceConfig = {
      ExecStart = "-${repmgr}/bin/repmgr -f /etc/repmgr.conf --log-level=ERROR node check --role";
      StandardInput = "socket";
    };
  };
  systemd.services.repmgrd = {
    after = ["openssh.service" "postgresql.service"];
    wants = ["postgresql.service"];
    wantedBy = ["multi-user.target"];
    path = [repmgr];
    serviceConfig = {
      PIDFile = "/run/postgresql/repmgrd.pid";
      Type = "forking";
      User = "postgres";
      Group = "postgres";
    };
    script = ''
      repmgrd -f /etc/repmgr.conf --pid-file /run/postgresql/repmgrd.pid
    '';
  };

  environment.etc = {
    "repmgr.conf" = {
      text = repmgrConfig;
      user = "postgres";
      group = "postgres";
      mode = "0444";
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
