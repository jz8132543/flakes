{
  config,
  lib,
  pkgs,
  ...
}:
let
  sshPorts = lib.unique (
    [
      22
      (config.ports.ssh or 1022)
    ]
    ++ lib.filter (p: p != 80 && p != 443) (
      lib.mapAttrsToList (_: h: h.port) (config.programs.ssh.customHosts or { })
    )
  );

  dn42Cfg = config.services.dn42 or null;
  dn42Enabled = dn42Cfg != null && (dn42Cfg.enable or false);
  dn42Ports = lib.optionals dn42Enabled [
    dn42Cfg.ikePort
    dn42Cfg.natTPort
  ];
in
{
  config = lib.mkIf config.services.mihomo.enable {
    networking.nftables.tables.mihomo-process-bypass = {
      family = "inet";
      content = ''
        chain route_output {
          type route hook output priority mangle; policy accept;

          meta skuid 998 counter meta mark set meta mark | 0x1

          # 放行 SSH 端口直连，强制走主路由表绕过 Meta TUN，避免被 DNS 反查劫持至 CDN 边缘池
          ${lib.optionalString (sshPorts != [ ]) ''
            tcp dport { ${
              lib.concatMapStringsSep ", " toString sshPorts
            } } counter meta mark set meta mark | 0x1
          ''}

          # 放行 DN42 IKE 与 NAT-T (Mimic Fake-TCP) 端口，打标 0x1 查 main 表绕过 TUN
          ${lib.optionalString (dn42Ports != [ ]) ''
            udp sport { ${
              lib.concatMapStringsSep ", " toString dn42Ports
            } } counter meta mark set meta mark | 0x1
            udp dport { ${
              lib.concatMapStringsSep ", " toString dn42Ports
            } } counter meta mark set meta mark | 0x1
            tcp sport { ${
              lib.concatMapStringsSep ", " toString dn42Ports
            } } counter meta mark set meta mark | 0x1
            tcp dport { ${
              lib.concatMapStringsSep ", " toString dn42Ports
            } } counter meta mark set meta mark | 0x1
          ''}
        }
      '';
    };

    # Mihomo fwmark 0x1 防回环绝缘墙 (priority 8995)
    # 彻底杜绝打标 0x1 的直连/出站流量在无路由时掉入 TUN (table 2022) 形成死循环
    systemd.services.mihomo-loop-prevention = {
      description = "Mihomo fwmark 0x1 Anti-Loop Rule (priority 8995)";
      after = [ "network-pre.target" ];
      before = [ "mihomo.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.iproute2 ];
      script = ''
        while ip -4 rule del priority 8995 2>/dev/null; do :; done
        while ip -6 rule del priority 8995 2>/dev/null; do :; done
        ip -4 rule add fwmark 0x1/0x1 unreachable priority 8995
        ip -6 rule add fwmark 0x1/0x1 unreachable priority 8995
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}
