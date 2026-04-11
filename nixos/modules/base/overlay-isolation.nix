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
  overlayEnabled = tailscaleEnabled || easytierEnabled;

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
      "network-online.target"
      "nftables.service"
    ];
    before =
      lib.optionals tailscaleEnabled [ "tailscaled.service" ]
      ++ lib.optionals easytierEnabled [ "easytier.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.iproute2 ];
    script = ''
      set -eu

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
