{
  config,
  lib,
  pkgs,
  ...
}:
let
  easytierCfg = config.services.easytierMesh;
  tailscaleEnabled = config.services.tailscale.enable;
  easytierEnabled = easytierCfg.enable;
  dn42Cfg = config.services.dn42 or null;
  dn42Enabled = dn42Cfg != null && (dn42Cfg.enable or false);
  overlayEnabled = tailscaleEnabled || easytierEnabled || dn42Enabled;

  overlayTransportMark = "0x1";
  overlayRoutingPriority = "8990";

  tailscaleInterface = "tailscale0";
  easytierInterface = easytierCfg.devName;

  tailscaleTransportUdpPorts = lib.optionals tailscaleEnabled [
    3478
    config.services.tailscale.port
  ];
  easytierTransportUdpPorts = lib.optionals easytierEnabled [ easytierCfg.protocols.quic.port ];
  easytierTransportTcpPorts = lib.optionals easytierEnabled [
    easytierCfg.protocols.wss.port
    easytierCfg.protocols.faketcp.port
  ];
in
lib.mkIf overlayEnabled {
  networking.nftables = {
    enable = true;
    tables.overlay-underlay-isolation = {
      family = "inet";
      content = ''
        chain route_output {
          type route hook output priority mangle; policy accept;

          # 将 overlay 的传输套接字留在物理 underlay 上。
          ${lib.optionalString (tailscaleTransportUdpPorts != [ ]) ''
            udp dport { ${lib.concatMapStringsSep ", " toString tailscaleTransportUdpPorts} } \
              counter meta mark set meta mark | ${overlayTransportMark}
            udp sport { ${lib.concatMapStringsSep ", " toString tailscaleTransportUdpPorts} } \
              counter meta mark set meta mark | ${overlayTransportMark}
          ''}
          ${lib.optionalString (easytierTransportUdpPorts != [ ]) ''
            udp dport { ${lib.concatMapStringsSep ", " toString easytierTransportUdpPorts} } \
              counter meta mark set meta mark | ${overlayTransportMark}
            udp sport { ${lib.concatMapStringsSep ", " toString easytierTransportUdpPorts} } \
              counter meta mark set meta mark | ${overlayTransportMark}
          ''}
          ${lib.optionalString (easytierTransportTcpPorts != [ ]) ''
            tcp dport { ${lib.concatMapStringsSep ", " toString easytierTransportTcpPorts} } \
              counter meta mark set meta mark | ${overlayTransportMark}
            tcp sport { ${lib.concatMapStringsSep ", " toString easytierTransportTcpPorts} } \
              counter meta mark set meta mark | ${overlayTransportMark}
          ''}
        }

        chain output {
          type filter hook output priority filter; policy accept;

          # 强制阻断递归封装：这里被标记过的传输流量绝不能
          # 再送入另一个 overlay 设备。
          meta mark & ${overlayTransportMark} == ${overlayTransportMark} oifname "${tailscaleInterface}" counter reject with icmpx type admin-prohibited
          meta mark & ${overlayTransportMark} == ${overlayTransportMark} oifname "${easytierInterface}" counter reject with icmpx type admin-prohibited
        }
      '';
    };
  };

  systemd.services.overlay-underlay-main = {
    description = "将 overlay 传输固定在主路由表";
    after = [
      "network-pre.target"
      "nftables.service"
    ]
    ++ lib.optionals dn42Enabled [ "dn42-policy-routing.service" ];
    before =
      lib.optionals tailscaleEnabled [ "tailscaled.service" ]
      ++ lib.optionals easytierEnabled [ "easytier.service" ]
      ++ lib.optionals dn42Enabled [
        "strongswan-swanctl.service"
        "bird.service"
      ];
    wants = [ "network-pre.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.iproute2 ];
    script = ''
      set -eu

      # ── 1. 清理已废弃的 table 200 (sdn_accel) 策略路由规则 ──
      # 注意：严禁删除 Priority 8980！Priority 8980 是 mihomo-routing 的 uid 998 查 main 表规则，若误删会导致 mihomo 出站被 8985 熔断从而全机断网
      while ip -4 rule del priority 9999 2>/dev/null; do :; done
      while ip -6 rule del priority 9999 2>/dev/null; do :; done

      # ── 2. Priority 8990: Overlay 流量打标直通 main 表 ──
      # 注：DN42 专有底层规则 (Priority 80/81/90) 由 dn42/base.nix 单点维护持有完整集群端口，避免多服务并发写入冲突
      priority=${overlayRoutingPriority}
      mark=${overlayTransportMark}
      while ip -4 rule del fwmark "$mark/$mark" lookup main priority "$priority" 2>/dev/null; do :; done
      while ip -6 rule del fwmark "$mark/$mark" lookup main priority "$priority" 2>/dev/null; do :; done
      ip -4 rule add fwmark "$mark/$mark" lookup main priority "$priority" 2>/dev/null || true
      ip -6 rule add fwmark "$mark/$mark" lookup main priority "$priority" 2>/dev/null || true
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };
}
