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

  # SSH 端口直连 main 表的 FIB 规则。
  # 与上方 nftables route_output 的 dport 打标互为冗余：打标依赖 route hook 与 nat redirect
  # 的先后时序，而 FIB 规则在 Initial Route Lookup 阶段即生效，确保 SSH 恒定旁路 Meta TUN。
  sshDirectRules = lib.concatMapStringsSep "\n" (port: ''
    ip -4 rule add ipproto tcp dport ${toString port} lookup main priority 8996
    ip -6 rule add ipproto tcp dport ${toString port} lookup main priority 8996
  '') sshPorts;

  # 多播/组播流量直连 main 表的 FIB 规则。
  # table 2022 的 ::/1、8000::/2 与 224.0.0.0/3 会覆盖组播地址，若不放行，
  # mDNS / SSDP 等本地发现报文会被丢进 Meta TUN，源地址被篡改为 198.18.0.1 且永远到不了局域网。
  # IPv4 广播由 local 表 (priority 0) 先行接管，无需额外规则。
  multicastDirectRules = ''
    ip -4 rule add to 224.0.0.0/4 lookup main priority 8996
    ip -6 rule add to ff00::/8 lookup main priority 8996
  '';
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

    # Mihomo UID 级与 fwmark 0x1 防回环绝缘墙 + 本机出站 TUN 接管 (priority 8980 - 8998)
    # 8980/8985/8995 彻底杜绝 Mihomo 自身出站流量在初始路由阶段或断网缺省时掉入 TUN (table 2022) 形成自捕获死循环；
    # 8996/8998 则负责把普通本机进程的出站流量交还给 TUN，并保留 SSH 直连语义。
    systemd.services.mihomo-loop-prevention = {
      description = "Mihomo UID & fwmark Anti-Loop Policy Rules (priority 8980-8998)";
      after = [ "network-pre.target" ];
      before = [ "mihomo.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.iproute2 ];
      script = ''
        mihomoUid=${toString config.users.users.mihomo.uid}

        # 1. 幂等清理
        for prio in 8980 8985 8995 8996 8998; do
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

        # 5. Priority 8996: 必须恒定旁路 TUN 的本机流量（FIB 级生效，不依赖 nftables 打标时序）
        #    - SSH 端口：避免被 Meta 捕获后依赖 route hook 打标与 nat redirect 的先后顺序
        #    - 组播：mDNS / SSDP 等本地发现协议必须留在物理网卡，源地址不能被改成 198.18.0.1
        ${multicastDirectRules}

        ${sshDirectRules}

        # 6. Priority 8998: 其余未打标的本机出站流量送入 Mihomo TUN 表 2022。
        #    病因：Mihomo auto-route 只生成 `not from all iif lo` / `from 0.0.0.0 iif lo` 规则，
        #    且其 9002 (`not from all dport 53 lookup main suppress_prefixlength 0`) 会把所有
        #    非 DNS 的本机出站旁路到 main 表，导致浏览器等应用流量永不进入 Meta TUN，
        #    只能直连被污染的 DNS 结果而超时。
        #    本规则优先级高于 9002，故未打标流量在初始选路即落入 table 2022；
        #    8980/8985/8990/8995 与 DN42 的 80/81/90 全部位于更前优先级，豁免语义不变。
        #    8996 放行 SSH 与组播；DN42/Tailscale/EasyTier 网段与公共 DNS 地址在 table 2022
        #    中无路由，查询失败后自动按优先级续降至 main 表，行为与现状一致。
        #    IPv4 广播与环回地址由 local 表 (priority 0) 先行接管，ICMP/PMTUD 由 DN42 的
        #    priority 90 放行，Mihomo 自身出站由 8980/8985 熔断，均不受本规则影响。
        ip -4 rule add not fwmark 0x1/0x1 lookup 2022 priority 8998
        ip -6 rule add not fwmark 0x1/0x1 lookup 2022 priority 8998
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}
