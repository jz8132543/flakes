{
  config,
  pkgs,
  self,
  lib,
  ...
}: let
  # repmgr = config.services.postgresql.package.pkgs.repmgr;
  repmgr = pkgs.stdenv.mkDerivation rec {
    pname = "repmgr";
    version = "5.4.0";

    src = pkgs.fetchFromGitHub {
      owner = "EnterpriseDB";
      repo = "repmgr";
      rev = "v${version}";
      sha256 = "sha256-QUxLqCZIopvqDncpaA8bxm9MHvO6R6jPrcd8hF8lqQs=";
    };
    nativeBuildInputs = with pkgs; [flex];
    buildInputs = with pkgs; [postgresql_15 openssl zlib readline curl json_c];
    installPhase = ''
      mkdir -p $out/{bin,lib,share/postgresql/extension}
      cp repmgr{,d} $out/bin
      cp *.so       $out/lib
      cp *.sql      $out/share/postgresql/extension
      cp *.control  $out/share/postgresql/extension
    '';
    meta = with lib; {
      homepage = "https://repmgr.org/";
      description = "Replication manager for PostgreSQL cluster";
      license = licenses.postgresql;
      platforms = pkgs.postgresql.meta.platforms;
      maintainers = with maintainers; [zimbatm];
    };
  };
  repmgrConfig = ''
    node_id=${self.lib.data.hosts.${config.networking.hostName}.id}
    node_name='${config.networking.hostName}'
    conninfo='host=${config.networking.hostName}.ts.dora.im user=repmgr dbname=repmgr connect_timeout=500'
    data_directory='${config.services.postgresql.dataDir}'
    repmgr_bindir='${repmgr}/bin'
    pg_bindir='${config.services.postgresql.package}/bin'

    failover=automatic
    promote_command='${repmgr}/bin/repmgr standby promote -f /etc/repmgr.conf --log-to-file'
    follow_command='${repmgr}/bin/repmgr standby follow -f /etc/repmgr.conf --log-to-file --upstream-node-id=%n'

    service_start_command='sudo systemctl start postgresql.service'
    service_stop_command='sudo systemctl stop postgresql.service'
    service_restart_command'sudo systemctl restart postgresql.service'
    service_reload_command'sudo systemctl reload postgresql.service'
  '';
  postgresHome = "/var/lib/postgresql";
in {
  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    package = pkgs.postgresql_15;
    dataDir = "${postgresHome}/${config.services.postgresql.package.psqlSchema}";
    initdbArgs = ["-E UTF-8 -U postgres --locale=en_US.UTF-8"];
    logLinePrefix = "user=%u,db=%d,app=%a,client=%h ";
    extraPlugins = with pkgs;
      [
        pgpool
        pgbouncer
      ]
      ++ [repmgr];
    authentication = lib.mkForce ''
      local all all trust
      host all all 127.0.0.1/32 trust
      host all all 100.64.0.0/10 trust
      host all all fdef:6567:bd7a::/48 trust
    '';
    initialScript = pkgs.writeText "initialScript" ''
      create extension repmgr;
    '';
    settings = {
      password_encryption = "scram-sha-256";
      hot_standby = "on";
      wal_level = "logical";
      max_wal_senders = 10;
      max_replication_slots = 10;
      archive_mode = "on";
      archive_command = "/run/current-system/sw/bin/true";
      # Required for repmgrd
      shared_preload_libraries = "repmgr";
    };
    ensureDatabases = ["repmgr"];
    ensureUsers = [
      {
        name = "repmgr";
        ensureClauses = {superuser = true;};
      }
    ];
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
  users.users.postgres.createHome = true;
  users.users.postgres.home = pkgs.lib.mkForce postgresHome;
  security.sudo.extraRules = [
    {
      users = ["postgres"];
      runAs = "root";
      commands =
        map (command: {
          options = ["NOPASSWD"];
          command = "/run/current-system/sw/bin/systemctl ${command} postgresql.service";
        })
        ["start" "stop" "restart" "reload"];
    }
  ];

  # backup postgresql database
  services.postgresqlBackup = {
    enable = true;
    backupAll = true;
    compression = "zstd";
  };
  # services.restic.backups.b2.paths = [
  #   config.services.postgresqlBackup.location
  # ];
  # systemd.services."restic-backups-b2" = {
  #   requires = ["postgresqlBackup.service"];
  #   after = ["postgresqlBackup.service"];
  # };
}
