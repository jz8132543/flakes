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
  };

  config = mkIf cfg.enable {
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
        "proxy.config.config_dir" = "/var/lib/trafficserver/etc";
        "proxy.config.admin.user_id" = "trafficserver";
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
            for f in records.config storage.config cache.config ip_allow.yaml plugin.config; do
              if [ -f /etc/trafficserver/$f ] && [ ! -f /var/lib/trafficserver/etc/$f ]; then
                cp /etc/trafficserver/$f /var/lib/trafficserver/etc/$f
              fi
            done

            # 确保加载 stats_over_http 插件，供 Traffic Monitor 健康嗅探 /_astats
            if ! grep -q "stats_over_http.so" /var/lib/trafficserver/etc/plugin.config 2>/dev/null; then
              echo "stats_over_http.so /_astats" >> /var/lib/trafficserver/etc/plugin.config
            fi

            # 保证回源时保留客户端原始 Host 标头，避免替换为源站机器名导致回源命中 DERP
            if ! grep -q "pristine_host_hdr" /var/lib/trafficserver/etc/records.config 2>/dev/null; then
              echo "CONFIG proxy.config.url_remap.pristine_host_hdr INT 1" >> /var/lib/trafficserver/etc/records.config
            fi

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
    '';

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
          SERVICE="$1"
          ACTION="$2"
          exec ${pkgs.systemd}/bin/systemctl "$ACTION" "$SERVICE"
        '')
      ];
      serviceConfig = {
        Type = "oneshot";
        # t3c syncds may update non-revalidate ATS files and upstream requires
        # root for that operation. ATS itself continues running as its own user.
        User = "root";
        Group = "root";
        # 按照用户要求：全量释放 VPS 计算性能，暂不实施 cgroup 资源配额限制
      };
      script = ''
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
          # 快速查询控制节点公布的版本指纹 (超时 3 秒)
          VER_JSON=$(curl -k -fsS -m 3 "https://$ctrl/version.json" 2>/dev/null || curl -k -fsS -m 3 "https://$ctrl/api/version.json" 2>/dev/null || true)
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

        export TO_PASS="$(tr -d '\r\n' < "${config.sops.secrets."atc/ops_password".path}")"
        ${pkgs.trafficcontrol.t3c}/bin/t3c apply \
          --traffic-ops-url="https://$BEST_CONTROLLER" \
          --traffic-ops-user="${cfg.opsUser}" \
          --cache-host-name="${config.networking.hostName}" \
          --run-mode=syncds \
          --trafficserver-home=/var/lib/trafficserver \
          --traffic-ops-insecure=true \
          --no-confirm-service-action \
          --skip-os-check=true \
          --git=no

        if [ "$BEST_EPOCH" -gt 0 ]; then
          echo "$BEST_EPOCH" > "$LAST_EPOCH_FILE"
        fi

        # 同步完成后全量更新 /etc/trafficserver 软链，并通知 ATS 重载
        for f in /var/lib/trafficserver/etc/*; do
          base=$(basename "$f")
          rm -f "/etc/trafficserver/$base" 2>/dev/null || true
          ln -sf "$f" "/etc/trafficserver/$base" 2>/dev/null || true
        done
        ${pkgs.trafficserver}/bin/traffic_ctl config reload 2>/dev/null || true
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
      dynamicConfigOptions = {
        http = {
          middlewares = {
            atc-edge-https-redirect = {
              redirectScheme = {
                scheme = "https";
                permanent = true;
              };
            };
          };
          routers = {
            atc-edge-astats = {
              rule = "PathPrefix(`/_astats`)";
              service = "atc-edge";
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
            atc-edge = {
              loadBalancer = {
                servers = [ { url = "http://127.0.0.1:8089"; } ];
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
