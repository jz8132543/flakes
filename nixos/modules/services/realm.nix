{
  pkgs,
  nixosModules,
  ...
}:
{
  imports = [ nixosModules.services.restic ];

  # Realm relay service
  # Configuration is read from /etc/realm/*.toml (or any config format realm supports)
  # Users should manually manage files in /etc/realm/
  # Example config: /etc/realm/config.toml

  systemd.services.realm = {
    description = "Realm relay service";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = "5s";
      # realm reads all *.toml files in a directory when given a directory path
      # 参数说明（1C2G800M 单向：BDP = 800×125×130/1000 ≈ 13MB）：
      #   -n 1048576  : nofile 上限 = fs.file-max，支撑大量并发连接
      #   -p 1024     : pipe 容量 = 1024 页 × 4096B = 4MB/连接，覆盖 30% BDP，
      #                 减少 splice() 系统调用次数，降低单核 CPU 负载；
      #                 2GB RAM 下建议不超过 2048（避免大量连接耗尽内存）。
      # ExecStart = "${pkgs.realm-latest}/bin/realm -n 500000 -p 1024 -c /etc/realm/config.toml";
      ExecStart = "${pkgs.realm-latest}/bin/realm -c /etc/realm/config.toml";
      LimitNOFILE = 1048576;
      # Security hardening
      # User = "realm";
      # Group = "realm";
      # Allow binding to privileged ports if needed
      CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      LogsDirectory = "realm";
      WorkingDirectory = "/var/log/realm";
      ReadOnlyPaths = [ "/etc/realm" ];
      DynamicUser = true;
      MemoryDenyWriteExecute = true;
      PrivateDevices = true;
      ProtectClock = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectProc = "invisible";
      ProtectKernelTunables = true;
      AmbientCapabilities = [
        "CAP_NET_ADMIN"
        "CAP_NET_BIND_SERVICE"
      ];
    };
  };

  users.users.realm = {
    isSystemUser = true;
    group = "realm";
    description = "Realm relay service user";
  };

  users.groups.realm = { };

  systemd.tmpfiles.rules = [
    "d /etc/realm 0755 root root -"
  ];

  # Persist the config directory across reboots (for impermanence setups)
  environment.global-persistence = {
    directories = [
      "/etc/realm"
    ];
  };

  services.restic.backups.borgbase.paths = [ "/etc/realm" ];
}
