{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.atc.edge;

  recordsConfigFile = pkgs.writeText "records.config" ''
    # ==============================================================================
    # Micro-Edge Apache Traffic Server (ATS) Configuration
    # Stripped concurrency & Zero disk I/O logging for ultra-low spec VPS
    # High-performance reverse proxy for core backend application servers
    # ==============================================================================

    # 1. 锁死线程数与关闭多线程竞争 (保护单核极弱 CPU，杜绝线程上下文切换)
    CONFIG proxy.config.exec_thread.autoconfig.enabled INT 0
    CONFIG proxy.config.exec_thread.limit INT ${toString cfg.execThreads}
    CONFIG proxy.config.accept_threads INT 1
    CONFIG proxy.config.task_threads INT 1

    # 2. 内存缓存 (RAM Cache) LRU 策略
    CONFIG proxy.config.ram_cache.size INT ${toString (cfg.ramCacheSizeMb * 1024 * 1024)}
    CONFIG proxy.config.ram_cache_cutoff INT 4194304
    CONFIG proxy.config.ram_cache.algorithm INT 1
    CONFIG proxy.config.ram_cache.use_seen_filter INT 1

    # 3. HTTP 长连接复用与协议支持 (防 TLS 频繁握手 CPU 尖峰)
    CONFIG proxy.config.http.keep_alive_enabled_in INT 1
    CONFIG proxy.config.http.keep_alive_enabled_out INT 1
    CONFIG proxy.config.http.keep_alive_timeout_in INT ${toString cfg.keepAliveTimeoutIn}
    CONFIG proxy.config.http.keep_alive_timeout_out INT ${toString cfg.keepAliveTimeoutOut}
    CONFIG proxy.config.http.transaction_no_activity_timeout_in INT 120
    CONFIG proxy.config.http.transaction_active_timeout_in INT 900
    CONFIG proxy.config.http.websocket.enabled INT 1
    CONFIG proxy.config.http2.enabled INT 1

    # 4. 反向代理与缓存控制 (动态 API 穿透，静态资源加速)
    CONFIG proxy.config.http.cache.required_headers INT 2
    CONFIG proxy.config.http.cache.when_to_revalidate INT 0
    CONFIG proxy.config.http.forward.proxy_auth_to_parent INT 1
    CONFIG proxy.config.url_remap.remap_required INT 1
    CONFIG proxy.config.url_remap.pristine_host_hdr INT 1

    # 5. 彻底禁用访问日志与调试日志 (零磁盘 I/O，杜绝写坏闪存)
    CONFIG proxy.config.log.logging_enabled INT 0
    CONFIG proxy.config.diags.debug.enabled INT 0
    CONFIG proxy.config.diags.show_location INT 0
    CONFIG proxy.config.log.max_space_mb_for_logs INT 20
    CONFIG proxy.config.log.max_secs_per_buffer INT 60

    # 6. 连接控制
    CONFIG proxy.config.net.connections_throttle INT 256
    CONFIG proxy.config.http.server_max_connections INT 128

    # 7. 回源与健康探针支持
    CONFIG proxy.config.http.connect_attempts_timeout INT 15
    CONFIG proxy.config.http.connect_attempts_max_retries INT 3
    ${cfg.extraRecordsConfig}
  '';

  storageConfigFile = pkgs.writeText "storage.config" (
    if cfg.cacheMode == "tmpfs" then
      "/dev/shm/ats-cache.db ${toString cfg.cacheSizeMb}M\n"
    else
      "/var/cache/trafficserver/cache.db ${toString cfg.cacheSizeMb}M\n"
  );

  loggingYamlFile = pkgs.writeText "logging.yaml" ''
    # Zero logging to prevent disk I/O blocking
    logging:
      formats: []
      filters: []
      logs: []
  '';

  remapConfigFile = pkgs.writeText "remap.config" (
    concatStringsSep "\n" (
      cfg.remapRules
      ++ [
        # 内置健康检查探针端点支持
        "map http://127.0.0.1:${toString cfg.statsPort}/_stats http://127.0.0.1:${toString cfg.statsPort}/_stats"
      ]
    )
  );

  t3cScript = pkgs.writeShellScript "run-t3c-sync" ''
    set -euo pipefail
    T3C_BIN="${cfg.t3c.package}/bin/t3c"
    if [ ! -x "$T3C_BIN" ]; then
      T3C_BIN="$(command -v t3c || true)"
    fi

    if [ -z "$T3C_BIN" ]; then
      echo "[t3c-sync] t3c binary not found in package, skipping sync" >&2
      exit 0
    fi

    PASS_ARG=""
    if [ -n "${toString cfg.t3c.passwordFile}" ] && [ -f "${toString cfg.t3c.passwordFile}" ]; then
      PASS_ARG="--traffic-ops-password-file=${cfg.t3c.passwordFile}"
    fi

    exec "$T3C_BIN" apply \
      --traffic-ops-url="${cfg.t3c.trafficOpsUrl}" \
      --traffic-ops-user="${cfg.t3c.username}" \
      $PASS_ARG \
      --run-mode=syncds \
      --cache-host-name="${config.networking.hostName}" \
      --git=no
  '';
in
{
  options.services.atc.edge = {
    enable = mkEnableOption "Ultra-minimal Apache Traffic Server edge reverse proxy with t3c sync";

    package = mkOption {
      type = types.package;
      default = pkgs.trafficserver;
      description = "Apache Traffic Server package to use (ATS 9.2.x)";
    };

    cacheMode = mkOption {
      type = types.enum [
        "tmpfs"
        "disk"
      ];
      default = "tmpfs";
      description = "Storage backing for ATS cache. 'tmpfs' avoids flash I/O on fragile nodes.";
    };

    cacheSizeMb = mkOption {
      type = types.int;
      default = 512;
      description = "Cache allocation size in Megabytes (hard limit <= 5GB)";
    };

    ramCacheSizeMb = mkOption {
      type = types.int;
      default = 64;
      description = "In-memory RAM cache size in Megabytes";
    };

    execThreads = mkOption {
      type = types.int;
      default = 1;
      description = "Number of event execution threads (1 or 2 for weak VPS)";
    };

    keepAliveTimeoutIn = mkOption {
      type = types.int;
      default = 600;
      description = "Client keep-alive timeout in seconds (default 10m to avoid TLS handshake spikes)";
    };

    keepAliveTimeoutOut = mkOption {
      type = types.int;
      default = 300;
      description = "Origin keep-alive timeout in seconds";
    };

    publicPorts = mkOption {
      type = types.listOf types.port;
      default = [
        80
        443
      ];
      description = "Public listening ports for client traffic";
    };

    statsPort = mkOption {
      type = types.port;
      default = 8404;
      description = "Internal monitoring port for Traffic Monitor astats scraping";
    };

    remapRules = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "map https://cloud.dora.im/ https://nue0.dora.im:443/"
        "map https://media.dora.im/ https://nue0.dora.im:8443/"
        "map https://app.dora.im/ https://can0.dora.im:443/"
      ];
      description = "List of reverse proxy mapping rules from domain to core application backends";
    };

    extraRecordsConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Extra configuration lines appended to records.config";
    };

    t3c = {
      enable = mkOption {
        type = types.bool;
        default = false; # Default false if using declarative remapRules, can be enabled when TO is active
        description = "Enable scheduled t3c config sync from Traffic Ops";
      };

      package = mkOption {
        type = types.package;
        default = pkgs.trafficcontrol;
        description = "Package providing t3c binary (built from Apache Traffic Control suite)";
      };

      trafficOpsUrl = mkOption {
        type = types.str;
        default = "https://nue0.dora.im:443";
        description = "URL for Traffic Ops API";
      };

      username = mkOption {
        type = types.str;
        default = "edge_sync";
        description = "Traffic Ops service account user";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to password file for t3c authentication";
      };

      interval = mkOption {
        type = types.str;
        default = "*:0/15"; # Every 15 minutes
        description = "Systemd OnCalendar interval for t3c sync";
      };
    };
  };

  config = mkIf cfg.enable {
    # 开放端口（标准放行，绝不添加任何 DROP 规则，完全不影响边缘机器上运行的其他服务）
    networking.firewall.allowedTCPPorts = cfg.publicPorts ++ [ cfg.statsPort ];

    # 用户与目录结构
    users.users.trafficserver = {
      isSystemUser = true;
      group = "trafficserver";
      description = "Apache Traffic Server daemon user";
    };
    users.groups.trafficserver = { };

    systemd.tmpfiles.rules = [
      "d /etc/trafficserver 0755 trafficserver trafficserver -"
      "d /var/log/trafficserver 0755 trafficserver trafficserver -"
      "d /var/run/trafficserver 0755 trafficserver trafficserver -"
      "d /var/cache/trafficserver 0750 trafficserver trafficserver -"
    ];

    # 下发精简配置文件与反向代理映射规则
    environment.etc."trafficserver/records.config".source = recordsConfigFile;
    environment.etc."trafficserver/storage.config".source = storageConfigFile;
    environment.etc."trafficserver/logging.yaml".source = loggingYamlFile;
    environment.etc."trafficserver/remap.config".source = remapConfigFile;

    # ATS 守护进程 (受严格 cgroup 限制，防止单核打满崩溃)
    systemd.services.trafficserver = {
      description = "Apache Traffic Server (Edge CDN Reverse Proxy & Cache)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "trafficserver";
        Group = "trafficserver";
        Restart = "always";
        RestartSec = "5s";

        # 资源熔断保护：CPU 限制 85%，内存上限 350M
        CPUQuota = "85%";
        MemoryMax = "350M";
        MemoryHigh = "300M";
        LimitNOFILE = 65536;

        ExecStart = "${cfg.package}/bin/traffic_server";
        ExecReload = "${cfg.package}/bin/traffic_ctl config reload";
      };
    };

    # t3c 周期降频同步任务 (15分钟一次，防止频繁解析耗尽算力)
    systemd.services.t3c-sync = mkIf cfg.t3c.enable {
      description = "Apache Traffic Control t3c configuration sync";
      after = [
        "network-online.target"
        "trafficserver.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        CPUQuota = "25%";
        MemoryMax = "128M";
        ExecStart = "${t3cScript}";
      };
    };

    systemd.timers.t3c-sync = mkIf cfg.t3c.enable {
      description = "Timer for periodic t3c configuration sync";
      timerConfig = {
        OnCalendar = cfg.t3c.interval;
        RandomizedDelaySec = "60s";
        Persistent = true;
      };
      wantedBy = [ "timers.target" ];
    };
  };
}
