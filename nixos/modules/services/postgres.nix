{
  config,
  lib,
  pkgs,
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

  # 2. 在 tailscale-setup 登录完成后，通过 tailscale set 宣告此 /32 路由并接受路由（无需重新登录）
  systemd.services.tailscale-advertise-postgres = {
    description = "Auto setup tailscale and assign static IP";
    after = [
      "network-online.target"
      "tailscaled.service"
      "tailscale-setup.service"
    ];
    wants = [
      "network-online.target"
      "tailscale-setup.service"
    ];
    wantedBy = [ "multi-user.target" ];

    # 确保脚本里有 iproute2 工具
    path = with pkgs; [
      config.services.tailscale.package
      pkgs.iproute2
      pkgs.coreutils
    ];

    script = ''
      # 1. 确保本地 lo 接口必定拥有该 IP，保证本机发给自己的流量命中 local 路由表（回环直通）
      ip addr replace ${STATIC_IP}/32 dev lo

      # 2. 等待 Tailscale 状态就绪
      for _ in $(seq 1 30); do
        if tailscale status >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done

      # 3. 宣告虚拟静态 IP 路由并开启路由接收
      tailscale set --advertise-routes=${STATIC_IP}/32 --accept-routes
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5";
    };
  };
}
