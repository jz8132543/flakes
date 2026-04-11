{
  config,
  lib,
  pkgs,
  ...
}:
let
  tailscaleUdpPorts = lib.optionals config.services.tailscale.enable [
    3478
    config.services.tailscale.port
  ];
  easytierUdpPorts = lib.optionals config.services.easytierMesh.enable [
    config.ports.easytier-quic
  ];
  easytierTcpPorts = lib.optionals config.services.easytierMesh.enable [
    config.services.easytierMesh.protocols.wss.port
    config.ports.easytier-faketcp
  ];
  udpPorts = tailscaleUdpPorts ++ easytierUdpPorts;
  tcpPorts = easytierTcpPorts;
  afterUnits = [
    "network-online.target"
    "nftables.service"
    "mihomo.service"
    "dnsmasq.service"
  ]
  ++ lib.optionals config.services.tailscale.enable [ "tailscaled.service" ]
  ++ lib.optionals config.services.easytierMesh.enable [ "easytier.service" ];
in
{
  config =
    lib.mkIf
      (
        config.services.mihomo.enable
        && (!config.services.easytierMesh.enable)
        && (udpPorts != [ ] || tcpPorts != [ ])
      )
      {
        networking.nftables = {
          enable = lib.mkDefault true;
          tables.vpn-overlay-isolation = {
            family = "inet";
            content = ''
              chain route_output {
                type route hook output priority mangle; policy accept;

                # 将 overlay/bootstrap 的传输流量固定在主路由表，
                # 这样 Mihomo 的 Meta TUN 就不会抓走这些套接字。
                ${lib.optionalString (udpPorts != [ ]) ''
                  udp dport { ${
                    lib.concatMapStringsSep ", " toString udpPorts
                  } } counter meta mark set meta mark | 0x1
                  udp sport { ${
                    lib.concatMapStringsSep ", " toString udpPorts
                  } } counter meta mark set meta mark | 0x1
                ''}
                ${lib.optionalString (tcpPorts != [ ]) ''
                  tcp dport { ${
                    lib.concatMapStringsSep ", " toString tcpPorts
                  } } counter meta mark set meta mark | 0x1
                  tcp sport { ${
                    lib.concatMapStringsSep ", " toString tcpPorts
                  } } counter meta mark set meta mark | 0x1
                ''}
              }
            '';
          };
        };

        systemd.services.vpn-overlay-isolation = {
          description = "将 Tailscale 和 EasyTier 的传输固定在主路由表";
          after = afterUnits;
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          path = [ pkgs.iproute2 ];
          script = ''
            while ip rule del fwmark 0x1/0x1 lookup main priority 8990 2>/dev/null; do :; done
            ip rule add fwmark 0x1/0x1 lookup main priority 8990
          '';
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
        };

        systemd.services.dnsmasq-direct-routing = {
          description = "将 dnsmasq 的上游查询固定在主路由表";
          after = afterUnits;
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          path = [
            pkgs.iproute2
            pkgs.coreutils
          ];
          script = ''
            DNSMASQ_UID=$(${pkgs.coreutils}/bin/id -u dnsmasq)

            while ip rule del uidrange "$DNSMASQ_UID-$DNSMASQ_UID" lookup main priority 8988 2>/dev/null; do :; done
            while ip -6 rule del uidrange "$DNSMASQ_UID-$DNSMASQ_UID" lookup main priority 8988 2>/dev/null; do :; done

            ip rule add uidrange "$DNSMASQ_UID-$DNSMASQ_UID" lookup main priority 8988
            ip -6 rule add uidrange "$DNSMASQ_UID-$DNSMASQ_UID" lookup main priority 8988
          '';
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
        };
      };
}
