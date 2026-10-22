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
  opsAddress =
    (findFirst (node: node.name == "fra0") { ipv4 = "94.249.174.75"; } cdnData.edgeNodes).ipv4;
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
      default = "ops.${config.networking.domain}";
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
    # Traffic Ops is not part of the CDN data-plane DNS zone. Keep edge sync
    # independent of an external ops.dora.im record being published.
    networking.extraHosts = "${opsAddress} ops.${config.networking.domain}";

    # 1. Apache Traffic Server 数据面配置与可写路径解耦
    services.trafficserver = {
      enable = true;
      records = {
        "proxy.config.config_dir" = "/var/lib/trafficserver/etc";
        "proxy.config.http.server_ports" = "8089 8089:ipv6";
      };
    };

    # 禁止使用 environment.etc."trafficserver/remap.config" 静态链接到 Nix Store
    environment.etc."trafficserver/remap.config".enable = false;

    # 预先创建 /run/t3c.lock，赋予 trafficserver 用户锁文件操作权限
    systemd.tmpfiles.rules = [
      "f /run/t3c.lock 0664 trafficserver trafficserver -"
      "d /var/lib/trafficcontrol-cache-config 0755 trafficserver trafficserver -"
      "d /var/lib/trafficcontrol-cache-config/status 0755 trafficserver trafficserver -"
    ];

    # 在 systemd.services.trafficserver.preStart 中完成基础结构初始化
    systemd.services.trafficserver.preStart = ''
      mkdir -p /var/lib/trafficserver/etc
      if [ ! -e /var/lib/trafficserver/etc/trafficserver ]; then
        ln -sf . /var/lib/trafficserver/etc/trafficserver
      fi

      # 仅在初次启动且不存在时初始基础配置，后续交由 t3c 全权接管
      if [ ! -f /var/lib/trafficserver/etc/remap.config ]; then
        touch /var/lib/trafficserver/etc/remap.config
      fi

      # 如果 /var/lib/trafficserver/etc 下尚无配置文件，先从默认配置模板种子一份
      for f in records.config storage.config cache.config ip_allow.yaml plugin.config; do
        if [ -f /etc/trafficserver/$f ] && [ ! -f /var/lib/trafficserver/etc/$f ]; then
          cp /etc/trafficserver/$f /var/lib/trafficserver/etc/$f
        fi
      done

      # 保证 /etc/trafficserver/remap.config 软链接至可写的运行时配置
      rm -f /etc/trafficserver/remap.config 2>/dev/null || true
      ln -sf /var/lib/trafficserver/etc/remap.config /etc/trafficserver/remap.config || true

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
        trafficcontrol
        trafficserver
        systemd
        curl
        iproute2
        gnugrep
        coreutils
        diffutils
        procps
      ];
      serviceConfig = {
        Type = "oneshot";
        # t3c syncds may update non-revalidate ATS files and upstream requires
        # root for that operation. ATS itself continues running as its own user.
        User = "root";
        Group = "root";
        # 低配 VPS 资源隔离
        MemoryHigh = "64M";
        MemoryMax = "96M";
        CPUQuota = "20%";
      };
      script = ''
        if [ ! -f "${config.sops.secrets."atc/ops_password".path}" ]; then
          echo "Traffic Ops password secret not found; skipping sync."
          exit 0
        fi

        export TO_PASS="$(cat "${config.sops.secrets."atc/ops_password".path}" | tr -d '\r\n')"
        if [ -z "$TO_PASS" ]; then
          echo "Traffic Ops password is empty; skipping sync."
          exit 0
        fi

        # Pre-check if Traffic Ops API is reachable to avoid noisy errors during startup
        # Traffic Ops 8 exposes the health endpoint under the versioned v4
        # API path; /api/v4/ping is not a valid route and would make every
        # edge silently skip t3c synchronization.
        if ! curl -k -s -f -m 5 "https://${cfg.opsHost}/api/4.0/ping" >/dev/null 2>&1; then
          echo "Traffic Ops API at https://${cfg.opsHost} is not reachable yet; skipping sync."
          exit 0
        fi

        touch /run/t3c.lock 2>/dev/null || true

        exec ${pkgs.trafficcontrol}/bin/t3c apply \
          --traffic-ops-url=https://${cfg.opsHost} \
          --traffic-ops-user=${cfg.opsUser} \
          --cache-host-name=${config.networking.hostName} \
          --run-mode=syncds \
          --trafficserver-home=/var/lib/trafficserver \
          --skip-os-check=true \
          --git=no
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

    networking.firewall.allowedTCPPorts = mkDefault [
      80
      443
    ];
  };
}
