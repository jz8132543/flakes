{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.atc.edge;
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
    # 1. Apache Traffic Server 数据面配置与可写路径解耦
    services.trafficserver = {
      enable = true;
      records = {
        "proxy.config.config_dir" = "/var/lib/trafficserver/etc";
      };
    };

    # 禁止使用 environment.etc."trafficserver/remap.config" 静态链接到 Nix Store
    environment.etc."trafficserver/remap.config".enable = false;

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
        iproute2
        gnugrep
        coreutils
        diffutils
        procps
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "trafficserver";
        Group = "trafficserver";
        # 低配 VPS 资源隔离
        MemoryHigh = "64M";
        MemoryMax = "96M";
        CPUQuota = "20%";
        ExecStart = ''
          ${pkgs.trafficcontrol}/bin/t3c apply \
            --traffic-ops-url=https://${cfg.opsHost} \
            --traffic-ops-user=${cfg.opsUser} \
            --traffic-ops-password-file=${config.sops.secrets."atc/ops_password".path} \
            --cache-host-name=${config.networking.hostName} \
            --run-mode=syncds \
            --trafficserver-home=/var/lib/trafficserver \
            --git=no
        '';
      };
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
