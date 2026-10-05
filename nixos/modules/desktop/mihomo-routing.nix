{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.services.mihomo.enable {
    networking.nftables.tables.mihomo-process-bypass = {
      family = "inet";
      content = ''
        chain route_output {
          type route hook output priority mangle; policy accept;

          meta skuid 998 counter meta mark set meta mark | 0x1
        }
      '';
    };

    systemd.services.mihomo-direct-routing = {
      description = "Route Mihomo outbound connections through the main table";
      after = [
        "network-online.target"
        "nftables.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.iproute2 ];
      script = ''
        while ip rule del fwmark 0x1/0x1 lookup main priority 8989 2>/dev/null; do :; done
        ip rule add fwmark 0x1/0x1 lookup main priority 8989
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}
