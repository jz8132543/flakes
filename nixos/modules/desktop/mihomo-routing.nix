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

    # Mihomo UID 级与 fwmark 0x1 防回环绝缘墙 (priority 8980 - 8995)
    # 彻底杜绝 Mihomo 自身出站流量在初始路由阶段或断网缺省时掉入 TUN (table 2022) 形成自捕获死循环
    systemd.services.mihomo-loop-prevention = {
      description = "Mihomo UID & fwmark Anti-Loop Policy Rules (priority 8980-8995)";
      after = [ "network-pre.target" ];
      before = [ "mihomo.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.iproute2 ];
      script = ''
        mihomoUid=${toString config.users.users.mihomo.uid}

        # 1. 幂等清理
        for prio in 8980 8985 8995; do
          while ip -4 rule del priority $prio 2>/dev/null; do :; done
          while ip -6 rule del priority $prio 2>/dev/null; do :; done
        done

        # 2. Priority 8980: Mihomo 守护进程 (uid 998) 自身发起的任何连接，在初次路由 (Initial Route Lookup)
        #    阶段强制查 main 表。由于在选源 IP 和出站网卡前就命中该规则，出站网卡直接选定物理网卡 (Wi-Fi/eth0)
        #    或专网网卡 (dn42x-*)，源 IP 自动绑定物理/内网 IP，绝不可能被选为 dev Meta (198.18.0.1)！
        ip -4 rule add uidrange $mihomoUid-$mihomoUid lookup main priority 8980
        ip -6 rule add uidrange $mihomoUid-$mihomoUid lookup main priority 8980

        # 3. Priority 8985: 当物理网络断开、Wi-Fi 漫游中或 main 表无默认网关时，Mihomo 自身的外部连接
        #    在此处直接熔断 (unreachable, 0ms 瞬间返回 ENETUNREACH)，彻底切断其掉入 priority 9003 (table 2022 / TUN)
        #    产生数万自捕获死循环连接的后路，杜绝 CPU 100% 与系统资源耗尽！
        ip -4 rule add uidrange $mihomoUid-$mihomoUid unreachable priority 8985
        ip -6 rule add uidrange $mihomoUid-$mihomoUid unreachable priority 8985

        # 4. Priority 8995: 针对经由 nftables 打标 0x1 的出站直连/放行流量 (SSH/DN42等)，无路由时同样熔断防回流
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
