{
  config,
  lib,
  nixosModules,
  ...
}:
let
  STATIC_IP = "10.222.222.1";
in
{
  imports = [ nixosModules.services.restic ];
  networking.firewall.allowedTCPPorts = [ 5432 ];
  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    # package = pkgs.postgresql_17;
    extensions =
      ps: with ps; [
        pgvector
        pg_search
      ];
    authentication = lib.mkForce ''
      local all all                           trust
      host all all 127.0.0.1/32               trust
      host all all ::1/128                    trust
      host all all 100.64.0.0/10              trust
      host all all ${STATIC_IP}/32            trust
      host all all fd7a:115c:a1e0::/48        trust
      host replication all 100.64.0.0/10      trust
      host replication all ${STATIC_IP}/32    trust
      host replication all fd7a:115c:a1e0::/48 trust
    '';
    settings = {
      max_connections = 300;
      shared_preload_libraries = "pg_search";
      password_encryption = "scram-sha-256";
      hot_standby = "on";
      wal_level = "logical";
      max_wal_senders = 10;
      max_replication_slots = 10;
      archive_mode = "on";
      archive_command = "/run/current-system/sw/bin/true";
      wal_log_hints = "on";
      log_line_prefix = "user=%u,db=%d,app=%a,client=%h";
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
    # requires = ["postgresqlBackup.service"];
    after = [ "postgresqlBackup.service" ];
  };

  # Prometheus PostgreSQL Exporter
  services.prometheus.exporters.postgres = {
    enable = true;
    port = config.ports.postgres-exporter;
    listenAddress = "127.0.0.1";
    runAsLocalSuperUser = true;
    dataSourceName = "user=postgres host=/run/postgresql dbname=postgres";
    extraFlags = [
      "--auto-discover-databases"
      "--exclude-databases=template0,template1"
    ];
  };

  systemd.services.prometheus-postgres-exporter = {
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    serviceConfig.SupplementaryGroups = [ "postgres" ];
  };

  systemd.services.postgresql.wants = [ "prometheus-postgres-exporter.service" ];

  systemd.services.postgresql.serviceConfig = {
    SystemCallFilter = lib.mkForce [
      "@system-service"
      "~@privileged"
    ];
  };

  # Overlay 虚拟静态 IP 方案：
  # 强制告诉内核：加载 dummy 模块时，必须给我生成 1 张网卡 (dummy0)
  # boot.kernelModules = ["dummy"];
  # boot.extraModprobeConfig = ''
  #   options dummy numdummies=1
  # '';

  # 2. 声明式绑定 IP
  networking.interfaces.lo.ipv4.addresses = [
    {
      address = "127.0.0.1";
      prefixLength = 8;
    }
    {
      address = STATIC_IP;
      prefixLength = 32;
    }
  ];

  # Include the route in every background login/reconciliation, including --reset.
  services.tailscale.extraSetFlags = [
    "--advertise-routes=${STATIC_IP}/32"
    "--accept-routes"
  ];
}
