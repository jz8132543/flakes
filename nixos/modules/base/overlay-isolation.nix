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

  dn42IkePort = if dn42Enabled then dn42Cfg.ikePort else 500;
  dn42NatTPort = if dn42Enabled then dn42Cfg.natTPort else 4500;
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
    description = "将 overlay 传输与 DN42 路由固定在主路由表";
    after = [
      "network-pre.target"
      "nftables.service"
    ];
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
      while ip -4 rule del priority 8980 2>/dev/null; do :; done
      while ip -4 rule del priority 9999 2>/dev/null; do :; done
      while ip -6 rule del priority 8980 2>/dev/null; do :; done
      while ip -6 rule del priority 9999 2>/dev/null; do :; done

      ${lib.optionalString dn42Enabled ''
        # ── 2. Priority 80: IPsec ESP 协议直通 main 表 ──
        while ip -4 rule del priority 80 2>/dev/null; do :; done
        while ip -6 rule del priority 80 2>/dev/null; do :; done
        ip -4 rule add ipproto esp lookup main priority 80
        ip -6 rule add ipproto esp lookup main priority 80

        # ── 3. Priority 81: IKE 与 NAT-T (UDP+TCP) 端口直通 main 表 ──
        while ip -4 rule del priority 81 2>/dev/null; do :; done
        while ip -6 rule del priority 81 2>/dev/null; do :; done
        for proto in udp tcp; do
          for port in ${toString dn42IkePort} ${toString dn42NatTPort}; do
            ip -4 rule add ipproto $proto sport $port lookup main priority 81
            ip -4 rule add ipproto $proto dport $port lookup main priority 81
            ip -6 rule add ipproto $proto sport $port lookup main priority 81
            ip -6 rule add ipproto $proto dport $port lookup main priority 81
          done
        done

        # ── 4. Priority 90: DN42 内网段 (to/from 172.20.0.0/14 及 fd00::/8) 直通 main 表 ──
        while ip -4 rule del priority 90 2>/dev/null; do :; done
        while ip -6 rule del priority 90 2>/dev/null; do :; done
        ip -4 rule add to 172.20.0.0/14 lookup main priority 90
        ip -4 rule add from 172.20.0.0/14 lookup main priority 90
        ip -4 rule add to 10.0.0.0/8 lookup main priority 90
        ip -6 rule add to fd00::/8 lookup main priority 90
        ip -6 rule add from fd00::/8 lookup main priority 90
        ip -6 rule add to fe80::/10 lookup main priority 90
      ''}

      # ── 5. Priority 8990: Overlay 流量打标直通 main 表 ──
      priority=${overlayRoutingPriority}
      mark=${overlayTransportMark}
      while ip -4 rule del fwmark "$mark/$mark" lookup main priority "$priority" 2>/dev/null; do :; done
      while ip -6 rule del fwmark "$mark/$mark" lookup main priority "$priority" 2>/dev/null; do :; done
      ip -4 rule add fwmark "$mark/$mark" lookup main priority "$priority"
      ip -6 rule add fwmark "$mark/$mark" lookup main priority "$priority"
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };
}
