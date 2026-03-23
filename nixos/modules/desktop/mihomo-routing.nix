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
    config.ports.easytier-traefik-wss
    config.ports.easytier-faketcp
  ];
  udpPorts = tailscaleUdpPorts ++ easytierUdpPorts;
  tcpPorts = easytierTcpPorts;
  afterUnits = [
    "network-online.target"
    "nftables.service"
    "mihomo.service"
  ]
  ++ lib.optionals config.services.tailscale.enable [ "tailscaled.service" ]
  ++ lib.optionals config.services.easytierMesh.enable [ "easytier.service" ];
in
{
  config = lib.mkIf (config.services.mihomo.enable && (udpPorts != [ ] || tcpPorts != [ ])) {
    networking.nftables = {
      enable = lib.mkDefault true;
      tables.vpn-overlay-isolation = {
        family = "inet";
        content = ''
          chain route_output {
            type route hook output priority mangle; policy accept;

            # Keep overlay/bootstrap transport traffic on the main routing
            # table so Mihomo's Meta TUN cannot capture these sockets.
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
      description = "Keep Tailscale and EasyTier transport on the main routing table";
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
  };
}
