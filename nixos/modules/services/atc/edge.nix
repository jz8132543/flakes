{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.atc.edge;
  cdnData = (builtins.fromJSON (builtins.readFile ../../../../lib/data/data.json)).cdn;
  controlNodes = cdnData.controlNodes or [ ];
  tune = config.environment.networkTune;
  baselineRecords = (import ../../../../lib/data/atc-records.nix) // {
    "proxy.config.exec_thread.limit" = cfg.netThreads;
  };
  healthScript = "${pkgs.python3}/bin/python3 ${./edge-health.py}";
  healthConfig = pkgs.writeText "atc-edge-health.json" (
    builtins.toJSON (
      cfg.health
      // {
        trafficCtl = "${pkgs.trafficserver}/bin/traffic_ctl";
        systemctl = "${pkgs.systemd}/bin/systemctl";
        bandwidthMbps = tune.bandwidth;
        listenBacklog = baselineRecords."proxy.config.net.listen_backlog";
        remapConfig = "/var/lib/trafficserver/etc/remap.config";
        configDirectory = "/var/lib/trafficserver/etc";
        loadedConfigHash = "/var/lib/trafficcontrol-cache-config/loaded_config_hash";
      }
    )
  );
  healthCommand = "${healthScript} --config ${healthConfig}";
  t3cService = pkgs.writeShellScript "atc-t3c-service" ''
    set -euo pipefail
    if [ "$#" -ne 2 ] || [ "''${1%.service}" != trafficserver ] || [ "$2" != status ]; then
      echo 't3c only supports read-only trafficserver status' >&2
      exit 1
    fi
    pid=$(${pkgs.procps}/bin/pgrep -o -x traffic_manager) || exit 3
    printf 'Active: active (running)\nMain PID: %s\n' "$pid"
  '';
  storageTemplate = pkgs.writeText "atc-default-storage.config" config.services.trafficserver.storage;
  hostingTemplate = pkgs.writeText "atc-default-hosting.config" config.services.trafficserver.hosting;
  prepareStorage = pkgs.writeShellScript "atc-prepare-storage" ''
    set -euo pipefail
    storage=/var/lib/trafficserver/etc/storage.config
    if ! ${pkgs.gnugrep}/bin/grep -q '^[[:space:]]*[^#[:space:]]' "$storage" 2>/dev/null; then
      tmp=$(mktemp "$storage.XXXXXX")
      trap 'rm -f "$tmp"' EXIT
      cp ${storageTemplate} "$tmp"
      ${pkgs.gnugrep}/bin/grep -q '^[[:space:]]*[^#[:space:]]' "$tmp"
      chmod 0644 "$tmp"
      chown trafficserver:trafficserver "$tmp"
      mv -f "$tmp" "$storage"
    fi
    volume=/var/lib/trafficserver/etc/volume.config
    hosting=/var/lib/trafficserver/etc/hosting.config
    # TC emits volume=1 hosting even without Drive parameters. Keep implicit volume 0.
    if ! ${pkgs.gnugrep}/bin/grep -q '^[[:space:]]*[^#[:space:]]' "$volume" 2>/dev/null \
      && ! ${pkgs.gnugrep}/bin/grep -Eq '^[[:space:]]*[^#][^#]*volume=[^#]*[1-9]' "$storage" \
      && ${pkgs.gnugrep}/bin/grep -q 't3c-generate' "$hosting" 2>/dev/null \
      && ${pkgs.gnugrep}/bin/grep -Eq '^[[:space:]]*(hostname|domain)[^#]*volume=[^#]*[1-9]' "$hosting"; then
      tmp=$(mktemp "$hosting.XXXXXX")
      trap 'rm -f "$tmp"' EXIT
      cp ${hostingTemplate} "$tmp"
      chmod 0644 "$tmp"
      chown trafficserver:trafficserver "$tmp"
      mv -f "$tmp" "$hosting"
    fi
  '';
  preparePlugins = pkgs.writeShellScript "atc-prepare-plugins" ''
    set -euo pipefail
    plugin=/var/lib/trafficserver/etc/plugin.config
    touch "$plugin"
    tmp=$(mktemp "$plugin.XXXXXX")
    trap 'rm -f "$tmp"' EXIT
    ${pkgs.gawk}/bin/awk '!/^[[:space:]]*([^[:space:]]*\/)?stats_over_http\.so([[:space:]]|$)/ { print }
      END { print "stats_over_http.so /_astats" }' "$plugin" > "$tmp"
    chmod 0644 "$tmp"
    chown trafficserver:trafficserver "$tmp"
    if ! ${pkgs.diffutils}/bin/cmp -s "$tmp" "$plugin"; then mv -f "$tmp" "$plugin"; fi
    chmod 0644 "$plugin"
    chown trafficserver:trafficserver "$plugin"
  '';
  prepareRecords = pkgs.writeShellScript "atc-prepare-records" ''
    set -euo pipefail
    records=/var/lib/trafficserver/etc/records.config
    templates=/var/lib/trafficserver/etc/body_factory
    if [ ! -d "$templates" ]; then
      ln -sfnT ${pkgs.trafficserver}/etc/trafficserver/body_factory "$templates"
    fi

    # Repair the deployed untyped records and retain unrelated t3c settings.
    tmp=$(mktemp "$records.XXXXXX")
    trap 'rm -f "$tmp"' EXIT
    ${pkgs.gawk}/bin/awk '
      BEGIN {
        ${concatMapStringsSep "\n" (name: ''
          types["${name}"] = "${if isInt baselineRecords.${name} then "INT" else "STRING"}"
          defaults["${name}"] = "CONFIG ${name} ${
            if isInt baselineRecords.${name} then "INT" else "STRING"
          } ${toString baselineRecords.${name}}"
        '') (attrNames baselineRecords)}
        aliases["proxy.config.exec_thread.autoconfig.enabled"] = "proxy.config.exec_thread.autoconfig"
        aliases["proxy.config.ram_cache.size"] = "proxy.config.cache.ram_cache.size"
        fixed["proxy.config.admin.user_id"] = 1
        fixed["proxy.config.body_factory.template_sets_dir"] = 1
        fixed["proxy.config.http.server_ports"] = 1
        fixed["proxy.config.cache.ram_cache.size"] = 1
        fixed["proxy.config.net.listen_backlog"] = 1
        fixed["proxy.config.exec_thread.autoconfig"] = 1
        fixed["proxy.config.exec_thread.limit"] = 1
        fixed["proxy.config.http.cache.cache_responses_to_cookies"] = 1
        fixed["proxy.config.http.cache.ignore_authentication"] = 1
        fixed["proxy.config.http.cache.ignore_client_no_cache"] = 1
        fixed["proxy.config.http.cache.ignore_server_no_cache"] = 1
        fixed["proxy.config.http.cache.required_headers"] = 1
      }
      {
        typed = ($1 == "CONFIG" || $1 == "LOCAL")
        name = typed ? $2 : $1
        if (name == "proxy.config.config_dir") next
        if (name in aliases) name = aliases[name]
        if (name in defaults) {
          if (typed) {
            $2 = name
            records[name] = $0
          } else {
            sub(/^[[:space:]]*[^[:space:]]+[[:space:]]+/, "")
            records[name] = "CONFIG " name " " types[name] " " $0
          }
          next
        }
        print
      }
      END {
        PROCINFO["sorted_in"] = "@ind_str_asc"
        for (name in defaults) {
          print (name in fixed || !(name in records)) ? defaults[name] : records[name]
        }
      }
    ' "$records" > "$tmp"
    chmod 0644 "$tmp"
    chown trafficserver:trafficserver "$tmp"
    mv -f "$tmp" "$records"
  '';
in
{
  options.services.atc.edge = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Apache Traffic Server and ATC t3c dynamic config synchronization.";
    };

    opsHost = mkOption {
      type = types.str;
      default = cdnData.controlHost or "ops.${config.networking.domain}";
      defaultText = "ops.<networking.domain>";
      description = "Traffic Ops API host/domain for configuration synchronization.";
    };

    opsUser = mkOption {
      type = types.str;
      default = "t3c-sync";
      description = "Read-only Traffic Ops account username for edge synchronization.";
    };

    netThreads = mkOption {
      type = types.ints.positive;
      default = min 8 (max 1 tune.cpus);
      description = "Explicit ATS network threads, independent of the virtual host CPU topology.";
    };

    resources = {
      totalMemoryMaxMiB = mkOption {
        type = types.ints.positive;
        default = max 128 (builtins.floor (tune.ram * 0.75));
        description = "Combined ATS and configuration-download memory boundary; independent health/recovery stay outside this slice.";
      };
      memoryMaxMiB = mkOption {
        type = types.ints.positive;
        default = max 96 (builtins.floor (tune.ram * 0.55));
        description = "Hard memory boundary for the entire ATS manager/worker cgroup.";
      };
      memoryHighMiB = mkOption {
        type = types.ints.positive;
        default = builtins.floor (cfg.resources.memoryMaxMiB * 0.8);
        description = "ATS cgroup reclaim threshold, below the hard memory boundary.";
      };
      swapMaxMiB = mkOption {
        type = types.ints.unsigned;
        default = min 128 (builtins.floor (tune.ram * 0.1));
        description = "Bound ATS swap without imposing a CPUQuota.";
      };
      syncMemoryMaxMiB = mkOption {
        type = types.ints.positive;
        default = max 64 (builtins.floor (tune.ram * 0.3));
        description = "Hard memory boundary for short-lived t3c configuration downloads.";
      };
    };

    health = {
      interface = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Real egress interface to sample; null selects the lowest-metric default route. Monitor sees its statistics as logical eth0.";
      };
      intervalSec = mkOption {
        type = types.ints.between 5 10;
        default = 5;
        description = "Single-producer background statistics sampling interval.";
      };
      probeTimeoutSec = mkOption {
        type = types.ints.between 1 3;
        default = 2;
        description = "Timeout of each ATS status RPC and actual loopback HTTP probe.";
      };
      staleAfterSec = mkOption {
        type = types.ints.positive;
        default = 15;
        description = "Maximum sample age; stale bridge responses fail closed with HTTP 503.";
      };
      failureThreshold = mkOption {
        type = types.ints.positive;
        default = 2;
        description = "Consecutive confirmed worker failures before recovery.";
      };
      maxRecoveries = mkOption {
        type = types.ints.positive;
        default = 3;
        description = "Maximum start/restart attempts in the recovery window, including failed attempts.";
      };
      recoveryWindowSec = mkOption {
        type = types.ints.positive;
        default = 600;
        description = "Persistent rolling recovery budget window.";
      };
      cooldownSec = mkOption {
        type = types.ints.positive;
        default = 300;
        description = "Stop the manager and its listener during cooldown when the budget is exhausted.";
      };
      startupGraceSec = mkOption {
        type = types.ints.positive;
        default = 30;
        description = "Grace for a newly started ATS worker before confirming failure.";
      };
      actionTimeoutSec = mkOption {
        type = types.ints.positive;
        default = 105;
        description = "Bound systemctl start/restart/stop operations, including configuration lock wait.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.resources.memoryHighMiB < cfg.resources.memoryMaxMiB;
        message = "ATS MemoryHigh must be below MemoryMax.";
      }
      {
        assertion = cfg.resources.memoryMaxMiB < cfg.resources.totalMemoryMaxMiB;
        message = "The combined edge memory budget must exceed the ATS memory budget.";
      }
      {
        assertion = cfg.health.staleAfterSec > cfg.health.intervalSec;
        message = "ATS sample freshness must exceed one sampling interval.";
      }
    ];
    # ── 控制平面 IP 解析兜底映射 ──────────────────────────────────────────
    # 将所有控制节点直接写入 extraHosts，确保在公网 DNS 或隧道解析未就绪时也能可靠直连
    networking.extraHosts = concatMapStringsSep "\n" (
      c:
      "${c.ipv4} ${cfg.opsHost} ${c.name}-ops.${config.networking.domain} ${c.name}.${config.networking.domain}"
    ) controlNodes;

    # 1. Apache Traffic Server 数据面配置与可写路径解耦
    services.trafficserver = {
      enable = true;
      records = {
        "proxy.config.http.server_ports" = "8089";
      };
    };

    # ATS 用户与兼容别名（t3c 默认尝试探测 ats 用户名）
    users.users.ats = {
      isSystemUser = true;
      group = "trafficserver";
    };

    # 禁止使用 environment.etc."trafficserver/remap.config" 静态链接到 Nix Store
    environment.etc."trafficserver/remap.config".enable = false;

    # 预先创建 /run/t3c.lock 与插件目录软链及 service 兼容包装器
    systemd.tmpfiles.rules = [
      "f /run/t3c.lock 0664 trafficserver trafficserver -"
      "f /run/atc-edge-config.lock 0600 root root -"
      "d /run/trafficserver 0755 trafficserver trafficserver -"
      "d /var/lib/trafficcontrol-cache-config 0755 trafficserver trafficserver -"
      "d /var/lib/trafficcontrol-cache-config/status 0755 trafficserver trafficserver -"
      "f /var/lib/trafficcontrol-cache-config/status/ONLINE 0644 trafficserver trafficserver -"
      "d /var/lib/trafficserver/etc/dscp 0755 trafficserver trafficserver -"
      "L+ /var/lib/trafficserver/libexec - - - - ${pkgs.trafficserver}/libexec"
      "L+ /var/lib/trafficserver/bin - - - - ${pkgs.trafficserver}/bin"
      "L+ /usr/sbin/service - - - - ${pkgs.writeShellScript "service" ''
        SERVICE="''${1%.service}"
        ACTION="$2"
        exec ${pkgs.systemd}/bin/systemctl "$ACTION" "$SERVICE.service"
      ''}"
    ];

    # 在 systemd.services.trafficserver.preStart 中完成基础结构初始化
    systemd.services.trafficserver.preStart = ''
             exec 9>/run/atc-edge-config.lock
             ${pkgs.util-linux}/bin/flock -w 65 9
            mkdir -p /var/lib/trafficserver/etc/dscp
            ln -sfn ${pkgs.trafficserver}/libexec /var/lib/trafficserver/libexec
            ln -sfn ${pkgs.trafficserver}/bin /var/lib/trafficserver/bin
            ln -sfn /var/lib/trafficserver/etc/dscp /etc/trafficserver/dscp 2>/dev/null || true
            if [ ! -e /var/lib/trafficserver/etc/trafficserver ]; then
              ln -sf . /var/lib/trafficserver/etc/trafficserver
            fi

            # 仅在初次启动且不存在时初始基础配置，后续交由 t3c 全权接管
            if [ ! -f /var/lib/trafficserver/etc/remap.config ]; then
              touch /var/lib/trafficserver/etc/remap.config
            fi
            if [ ! -f /var/lib/trafficserver/etc/dscp/set_dscp_0.config ]; then
              cat <<'EOF' > /var/lib/trafficserver/etc/dscp/set_dscp_0.config
      cond %{REMAP_PSEUDO_HOOK}
      set-conn-dscp 0 [L]
      EOF
            fi

            # 如果 /var/lib/trafficserver/etc 下尚无配置文件，先从默认配置模板种子一份
             for f in records.config storage.config volume.config hosting.config cache.config ip_allow.yaml plugin.config; do
              if [ -f /etc/trafficserver/$f ] && [ ! -f /var/lib/trafficserver/etc/$f ]; then
                cp /etc/trafficserver/$f /var/lib/trafficserver/etc/$f
              fi
            done

             ${prepareStorage}
             ${preparePlugins}
            ${prepareRecords}

            # 清理陈旧锁文件并全量软链动态配置至 /etc/trafficserver/
            mkdir -p /run/trafficserver
            chown -R trafficserver:trafficserver /run/trafficserver
            chmod 0755 /run/trafficserver
            rm -f /run/trafficserver/*.lock /run/trafficserver/*.sock

            for f in /var/lib/trafficserver/etc/*; do
              base=$(basename "$f")
              rm -f "/etc/trafficserver/$base" 2>/dev/null || true
              ln -sf "$f" "/etc/trafficserver/$base" 2>/dev/null || true
            done

            touch /run/t3c.lock 2>/dev/null && chown trafficserver:trafficserver /run/t3c.lock 2>/dev/null || true
            chown -R trafficserver:trafficserver /var/lib/trafficserver
            ${healthScript} --digest /var/lib/trafficserver/etc > /var/lib/trafficcontrol-cache-config/loaded_config_hash
    '';
    systemd.services.trafficserver = {
      # Persistent recovery owns the budget; manual Nix activations must not consume it.
      startLimitIntervalSec = 0;
      startLimitBurst = 0;
      # No direct ATS/stats ingress can bypass Traefik's RemoteAddr allowlist.
      environment.PROXY_LOCAL_INCOMING_IP_TO_BIND = "127.0.0.1";
      serviceConfig = {
        # One recovery owner; automatic Restart must not fight cooldown stop.
        Restart = mkForce "no";
        TimeoutStartSec = "90s";
        TimeoutStopSec = "10s";
        # The upstream unit only kills the manager, leaving worker sockets alive.
        KillMode = "control-group";
        Slice = "atc-edge.slice";
        MemoryAccounting = true;
        MemoryHigh = "${toString cfg.resources.memoryHighMiB}M";
        MemoryMax = "${toString cfg.resources.memoryMaxMiB}M";
        MemorySwapMax = "${toString cfg.resources.swapMaxMiB}M";
        OOMPolicy = "stop";
      };
    };

    systemd.slices.atc-edge.sliceConfig = {
      MemoryAccounting = true;
      MemoryMax = "${toString cfg.resources.totalMemoryMaxMiB}M";
      MemorySwapMax = "${toString cfg.resources.swapMaxMiB}M";
    };

    systemd.services.atc-edge-health = {
      description = "Bounded ATS statistics and health bridge";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        User = "trafficserver";
        Group = "trafficserver";
        ExecStart = healthCommand;
        Restart = "on-failure";
        RestartSec = "5s";
        MemoryMax = "64M";
        MemorySwapMax = 0;
        TasksMax = 8;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_UNIX"
        ];
        IPAddressDeny = "any";
        IPAddressAllow = "localhost";
      };
    };

    systemd.services.atc-edge-recovery = {
      description = "Independent ATS worker recovery with persistent budget and cooldown";
      after = [ "atc-edge-health.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${healthCommand} --recover";
        TimeoutStartSec = cfg.health.actionTimeoutSec + 15;
        StateDirectory = "atc-edge-recovery";
        StateDirectoryMode = "0700";
        UMask = "0077";
        MemoryMax = "48M";
        MemorySwapMax = 0;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };
    systemd.timers.atc-edge-recovery = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "20s";
        OnUnitInactiveSec = "10s";
        AccuracySec = "1s";
      };
    };

    # 2. 凭据权限配置
    sops.secrets."atc/ops_password" = {
      owner = "trafficserver";
      group = "trafficserver";
      mode = "0400";
    };

    # 3. 创建 atc-t3c-sync 定时同步服务与 cgroup 配额
    systemd.services.atc-t3c-sync = {
      description = "Apache Traffic Control Edge Dynamic Config Sync";
      after = [
        "network-online.target"
        "trafficserver.service"
      ];
      wants = [ "network-online.target" ];
      path = with pkgs; [
        trafficcontrol.t3c
        trafficserver
        systemd
        curl
        jq
        iproute2
        gnugrep
        coreutils
        diffutils
        procps
        (pkgs.writeShellScriptBin "service" ''
          exec ${t3cService} "$@"
        '')
      ];
      serviceConfig = {
        Type = "oneshot";
        # t3c syncds may update non-revalidate ATS files and upstream requires
        # root for that operation. ATS itself continues running as its own user.
        User = "root";
        Group = "root";
        TimeoutStartSec = "85s";
        TimeoutStopSec = "10s";
        KillMode = "control-group";
        Slice = "atc-edge.slice";
        MemoryMax = "${toString cfg.resources.syncMemoryMaxMiB}M";
        MemorySwapMax = 0;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        # t3c cannot alter other services or global networking. Reload is our own RPC below.
        InaccessiblePaths = [
          "/run/systemd"
          "-/run/dbus"
        ];
        # TC uses this absolute SysV path even with --service-action=none.
        BindReadOnlyPaths = [ "${t3cService}:/usr/sbin/service" ];
        ReadWritePaths = [
          "/var/lib/trafficserver"
          "/var/lib/trafficcontrol-cache-config"
          "/etc/trafficserver"
          "/run/trafficserver"
          "/run/t3c.lock"
          "/run/atc-edge-config.lock"
        ];
      };
      script = ''
        set -euo pipefail
        exec 9>/run/atc-edge-config.lock
        ${pkgs.util-linux}/bin/flock -w 5 9 || exit 0

        # Keep the cache layout when t3c's missing Drive parameters produce empty files.
        ${prepareStorage}
        cache_snapshot=$(mktemp -d /var/lib/trafficserver/.cache-config.XXXXXX)
        cp /var/lib/trafficserver/etc/storage.config "$cache_snapshot/storage.config"
        for file in volume.config hosting.config; do
          if [ -f "/var/lib/trafficserver/etc/$file" ]; then
            cp "/var/lib/trafficserver/etc/$file" "$cache_snapshot/$file"
          else
            touch "$cache_snapshot/$file"
          fi
        done

        # Repair even after an interrupted/failed download. Never reload partial config.
        finish() {
          result=$?
          trap - EXIT
          if ! grep -q '^[[:space:]]*[^#[:space:]]' /var/lib/trafficserver/etc/storage.config 2>/dev/null; then
            cp "$cache_snapshot/storage.config" /var/lib/trafficserver/etc/storage.config
            cp "$cache_snapshot/volume.config" /var/lib/trafficserver/etc/volume.config
            cp "$cache_snapshot/hosting.config" /var/lib/trafficserver/etc/hosting.config
          fi
          rm -rf "$cache_snapshot"
          ${prepareStorage}
          ${prepareRecords}
          ${preparePlugins}
          for f in /var/lib/trafficserver/etc/*; do
            base=$(basename "$f")
            rm -f "/etc/trafficserver/$base" 2>/dev/null || true
            ln -sf "$f" "/etc/trafficserver/$base" 2>/dev/null || true
          done
          [ "$result" -eq 0 ] || exit "$result"
          hash=$(${healthScript} --digest /var/lib/trafficserver/etc)
          loaded=$(cat /var/lib/trafficcontrol-cache-config/loaded_config_hash 2>/dev/null || true)
          if [ "$hash" != "$loaded" ]; then
            status=$(timeout -k 1s 2s traffic_ctl server status 2>/dev/null || true)
            if [ "$status" = "Proxy -- on" ]; then
              timeout -k 1s 5s traffic_ctl config reload
              echo "$hash" > /var/lib/trafficcontrol-cache-config/loaded_config_hash
            else
              echo "ATS worker not on; leaving changed configuration pending without reload."
            fi
          fi
        }
        trap finish EXIT
        trap 'exit 143' TERM INT

        if [ ! -s "${config.sops.secrets."atc/ops_password".path}" ]; then
          echo "Traffic Ops password secret not found or empty; skipping sync."
          exit 0
        fi

        # ── 多控制节点探活、版本指纹提取与仲裁选优 ───────────────────────────
        # 候选控制节点列表：优先域名，其次各控制节点 FQDN
        CANDIDATE_CONTROLLERS=(
          "${cfg.opsHost}"
          ${concatMapStringsSep " " (
            c: ''"${c.name}-ops.${config.networking.domain}" "${c.name}.${config.networking.domain}"''
          ) controlNodes}
        )

        BEST_CONTROLLER="${cfg.opsHost}"
        BEST_EPOCH=0
        BEST_FINGERPRINT=""

        for ctrl in "''${CANDIDATE_CONTROLLERS[@]}"; do
          [ -z "$ctrl" ] && continue
          # 快速查询控制节点公布的版本指纹 (每个请求超时 1 秒)
          VER_JSON=$(curl -k -fsS -m 1 "https://$ctrl/version.json" 2>/dev/null || curl -k -fsS -m 1 "https://$ctrl/api/version.json" 2>/dev/null || true)
          if [ -n "$VER_JSON" ]; then
            EPOCH=$(echo "$VER_JSON" | jq -r '.epoch // 0' 2>/dev/null || echo 0)
            FP=$(echo "$VER_JSON" | jq -r '.fingerprint // "unknown"' 2>/dev/null || echo "unknown")
            echo "Probed control node $ctrl: epoch=$EPOCH, fingerprint=$FP"
            if [ "$EPOCH" -gt "$BEST_EPOCH" ]; then
              BEST_EPOCH="$EPOCH"
              BEST_CONTROLLER="$ctrl"
              BEST_FINGERPRINT="$FP"
            fi
          fi
        done

        # 若未成功探测到版本元数据，执行基础连通性回退
        if [ -z "$BEST_CONTROLLER" ]; then
          if curl -k -s -f -m 5 "https://${cfg.opsHost}/api/4.0/ping" >/dev/null 2>&1; then
            BEST_CONTROLLER="${cfg.opsHost}"
          else
            echo "All Traffic Ops control endpoints are unreachable; skipping sync."
            exit 0
          fi
        fi

        # ── 单调版本防倒退保护 (Anti-Rollback) ──────────────────────────────
        # 边缘节点记录已成功应用的最新版本 epoch。若选举出的控制节点版本落后于
        # 当前已生效的配置，则拒绝同步，防止边缘因控制节点临时网络抖动发生配置倒退。
        LAST_EPOCH_FILE="/var/lib/trafficcontrol-cache-config/applied_epoch"
        LAST_EPOCH=0
        if [ -f "$LAST_EPOCH_FILE" ]; then
          LAST_EPOCH=$(cat "$LAST_EPOCH_FILE" | tr -d '[:space:]' || echo 0)
        fi

        if [ "$BEST_EPOCH" -gt 0 ] && [ "$LAST_EPOCH" -gt 0 ] && [ "$BEST_EPOCH" -lt "$LAST_EPOCH" ]; then
          echo "WARNING: Selected controller $BEST_CONTROLLER (epoch $BEST_EPOCH) is OLDER than local applied epoch $LAST_EPOCH. Skipping sync to prevent rollback!"
          exit 0
        fi

        echo "Synchronizing configuration from active controller: $BEST_CONTROLLER (version: $BEST_FINGERPRINT, epoch: $BEST_EPOCH)..."
        touch /run/t3c.lock 2>/dev/null || true

        TO_PASS="$(tr -d '\r\n' < "${config.sops.secrets."atc/ops_password".path}")"
        export TO_PASS
        timeout -k 2s 60s ${pkgs.trafficcontrol.t3c}/bin/t3c apply \
          --traffic-ops-url="https://$BEST_CONTROLLER" \
          --traffic-ops-user="${cfg.opsUser}" \
          --cache-host-name="${config.networking.hostName}" \
          --run-mode=syncds \
          --trafficserver-home=/var/lib/trafficserver \
          --traffic-ops-insecure=true \
          --no-confirm-service-action \
          --service-action=none \
          --num-retries=1 \
          --traffic-ops-timeout-milliseconds=5000 \
          --skip-os-check=true \
          --git=no

        if [ "$BEST_EPOCH" -gt 0 ]; then
          echo "$BEST_EPOCH" > "$LAST_EPOCH_FILE"
        fi
      '';
    };

    systemd.timers.atc-t3c-sync = {
      description = "Periodic sync timer for Apache Traffic Control t3c";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "30s";
        RandomizedDelaySec = "5s";
      };
    };

    # 4. 边缘节点接入层：由 Traefik 统筹外部 TLS 终结并转发至本机 ATS 高速缓存
    # 80 端口仅做 HTTP→HTTPS 重定向，不反代任何业务流量；
    # 443 端口终结 TLS 后转发至 ATS，所有回源规则由 t3c 动态下发。
    services.traefik = {
      enable = mkDefault true;
      staticConfigOptions.entryPoints = {
        http = {
          # Traefik's default redirect priority is higher than every user router.
          http.redirections.entryPoint.priority = 1;
          proxyProtocol = {
            insecure = mkForce false;
            # Traefik rejects an enabled PROXY listener without trusted IPs.
            trustedIPs = mkForce [
              "127.0.0.1/32"
              "::1/128"
            ];
          };
        };
        https.proxyProtocol = {
          insecure = mkForce false;
          trustedIPs = mkForce [
            "127.0.0.1/32"
            "::1/128"
          ];
        };
      };
      dynamicConfigOptions = {
        http = {
          middlewares = {
            atc-edge-stats-allow = {
              # An unset ipStrategy uses the peer RemoteAddr, never X-Forwarded-For.
              ipAllowList.sourceRange = [
                "127.0.0.0/8"
                "::1/128"
              ]
              ++ concatMap (
                c:
                optional ((c.ipv4 or null) != null) "${c.ipv4}/32"
                ++ optional ((c.ipv6 or null) != null) "${c.ipv6}/128"
              ) controlNodes;
            };
            atc-edge-https-redirect = {
              redirectScheme = {
                scheme = "https";
                permanent = true;
              };
            };
          };
          routers = {
            atc-edge-astats = {
              rule = "Path(`/_astats`) || Path(`/healthz`)";
              service = "atc-edge-health";
              middlewares = [ "atc-edge-stats-allow" ];
              entryPoints = [
                "http"
                "https"
              ];
              priority = 1000;
            };
            atc-edge-http = {
              rule = concatMapStringsSep " || " (
                s: "Host(`${s}.${config.networking.domain}`) || Host(`${s}.cdn.${config.networking.domain}`)"
              ) (attrNames (cdnData.services or { }));
              entryPoints = [ "http" ];
              middlewares = [ "atc-edge-https-redirect" ];
              priority = 100;
            };
          };
          services = {
            atc-edge-health.loadBalancer.servers = [ { url = "http://127.0.0.1:9130"; } ];
            atc-edge = {
              loadBalancer = {
                servers = mkForce [ { url = "http://127.0.0.1:8089"; } ];
                # Override only the probe port: no traffic to a dead worker listener,
                # and no router recursion through the public /healthz endpoint.
                healthCheck = {
                  port = 9130;
                  path = "/healthz";
                  interval = "5s";
                  timeout = "2s";
                };
              };
            };
          };
        };
      };
      proxies.atc-edge = {
        rule = concatMapStringsSep " || " (
          s: "Host(`${s}.${config.networking.domain}`) || Host(`${s}.cdn.${config.networking.domain}`)"
        ) (attrNames (cdnData.services or { }));
        target = "http://127.0.0.1:8089";
        entryPoints = [ "https" ];
        priority = 100;
      };
    };

    networking.firewall.allowedTCPPorts = mkDefault [
      80
      443
    ];
  };
}
