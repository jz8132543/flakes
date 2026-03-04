{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.environment.networkTune;

  # ── 辅助：整数 clamp ────────────────────────────────────────────────
  clamp =
    lo: hi: v:
    if v < lo then
      lo
    else if v > hi then
      hi
    else
      v;

  # ── 核心：BDP（带宽延迟积）──────────────────────────────────────────
  # 使用 realBandwidth 来计算缓冲和窗口参数，避免基于理论上限产生溢出包风暴
  bdp = cfg.realBandwidth * cfg.rtt * 125;

  # ── Socket 缓冲区上限 (rmem_max / wmem_max) ─────────────────────────
  rmem_max_raw = bdp * 2;
  rmem_max_pct = cfg.ram * 131072; # 12.5% of RAM in bytes
  rmem_max_limit = 128 * 1024 * 1024; # 128 MB absolute ceiling
  rmem_max = clamp (16 * 1024 * 1024) rmem_max_limit (
    if rmem_max_raw < rmem_max_pct then rmem_max_raw else rmem_max_pct
  );

  # ── 默认缓冲区 (rmem_default / wmem_default) ─────────────────────────
  rmem_default_raw = bdp / 2;
  rmem_default = clamp (4 * 1024 * 1024) (rmem_max / 2) rmem_default_raw;

  # ── 待发送队列唤醒下限 (tcp_notsent_lowat) ──────────────────────────
  notsent_lowat_raw = bdp / 4;
  notsent_lowat = if notsent_lowat_raw < 2097152 then 2097152 else notsent_lowat_raw;

  # ── TCP/UDP 全局内存池（单位：页，1 页 = 4096 B）──────────────────
  tcp_mem_low = cfg.ram * 256 * 15 / 100; # = ram * 38
  tcp_mem_mid = cfg.ram * 256 * 30 / 100; # = ram * 77
  tcp_mem_high_raw = cfg.ram * 256 * 50 / 100; # = ram * 128
  tcp_mem_high_bw = rmem_max * 64 / 4096; # 64× max-conn cap in pages
  tcp_mem_high = if tcp_mem_high_raw < tcp_mem_high_bw then tcp_mem_high_raw else tcp_mem_high_bw;
  udp_mem_low = tcp_mem_low / 2;
  udp_mem_mid = tcp_mem_mid / 2;
  udp_mem_high = tcp_mem_high / 2;

  # ── 连接队列 ────────────────────────────────────────────────────────
  netdev_backlog =
    if cfg.bandwidth >= 5000 then
      500000
    else if cfg.bandwidth >= 2000 then
      300000
    else if cfg.bandwidth >= 1000 then
      100000
    else
      50000;

  syn_backlog =
    if cfg.ram >= 8192 then
      524288
    else if cfg.ram >= 4096 then
      262144
    else if cfg.ram >= 2048 then
      131072
    else if cfg.ram >= 1024 then
      65536
    else
      32768;

  tw_buckets =
    if cfg.ram >= 8192 then
      2000000
    else if cfg.ram >= 4096 then
      1000000
    else if cfg.ram >= 2048 then
      500000
    else if cfg.ram >= 1024 then
      200000
    else
      100000;

  max_orphans =
    if cfg.ram >= 8192 then
      131072
    else if cfg.ram >= 2048 then
      65536
    else if cfg.ram >= 1024 then
      32768
    else
      16384;

  # ── 文件描述符 & 管道 ───────────────────────────────────────────────
  file_max =
    if cfg.ram >= 8192 then
      2097152
    else if cfg.ram >= 2048 then
      1048576
    else
      524288;

  pipe_max = if cfg.ram >= 4096 then 8388608 else 4194304;

  # ── CPU 专项：NAPI 批处理 ────────────────────────────────────────────
  napi_budget =
    if cfg.cpus == 1 then
      1200
    else if cfg.cpus <= 4 then
      2000
    else
      3000;

  dev_weight = if cfg.cpus == 1 then 128 else 256;

  busy_poll = 0;

  # ── nf_conntrack ────────────────────────────────────────────────────
  conntrack_raw = cfg.ram * 1048576 * 5 / 100 / 300;
  conntrack_max = clamp 65536 2097152 conntrack_raw;

  # ── 初期接收窗口 (initrwnd) ──────────────────────────────────────────
  # 激进地基于 BDP 预留初始接收窗口。BDP(包数) = bdp(字节) / 1400。
  # 我们取 BDP 的 1/4 作为起步，并限定在 150 - 1024 之间。
  # 1024 个 MSS (约 1.4MB) 对现代内核的 initrwnd 是一个很激进但安全的上限。
  bdp_pkts = bdp / 1400;
  initrwnd_raw = bdp_pkts / 4;
  initrwnd =
    if initrwnd_raw < 150 then
      150
    else if initrwnd_raw > 1024 then
      1024
    else
      initrwnd_raw;

  # ── 重试次数 ────────────────────────────────────────────────────────
  syn_retries =
    if cfg.highLoss && cfg.cpus == 1 then
      3
    else if cfg.highLoss then
      4
    else
      6;

  synack_retries = if cfg.highLoss then 3 else 5;
  tcp_retries2 = if cfg.cpus == 1 && cfg.ram < 1024 then 6 else 8;

  # ── 内存/Swap ────────────────────────────────────────────────────────
  vm_swappiness = if cfg.ram >= 8192 then 5 else 10;

in
{
  options.environment.networkTune = {
    enable = (lib.mkEnableOption "hardware-aware network sysctl tuning") // {
      default = true;
    };

    bandwidth = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "单向目标带宽上限（Mbps）。";
    };

    realBandwidth = lib.mkOption {
      type = lib.types.int;
      default = builtins.floor (cfg.bandwidth * 0.6);
      description = "用于 BDP 和窗口计算的实际可用/持续带宽（Mbps）。默认取标称带的 60% 防止拥塞。";
    };

    rtt = lib.mkOption {
      type = lib.types.int;
      default = 200;
      description = "主要流量路径的预期 RTT（毫秒）。";
    };

    ram = lib.mkOption {
      type = lib.types.int;
      default = 1024;
      description = "可用物理内存（MB）。";
    };

    cpus = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "CPU 核心/线程数。";
    };

    highLoss = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "是否针对高丢包国际链路优化。";
    };
  };

  config = lib.mkMerge [
    {
      networking = {
        nftables.enable = true;
        firewall.enable = true;
        nameservers = lib.mkDefault [
          "1.1.1.1"
          "1.0.0.1"
          "223.5.5.5"
        ];
        domain = "dora.im";
        search = [ "dora.im" ];
        dhcpcd.extraConfig = "nohook resolv.conf";
      };

      environment.etc."gai.conf".text = ''
        label  ::1/128       0
        label  ::/0          1
        label  2002::/16     2
        label ::/96          3
        label ::ffff:0:0/96  4
        precedence  ::1/128       50
        precedence  ::/0          40
        precedence  2002::/16     30
        precedence ::/96          20
        precedence ::ffff:0:0/96  100
      '';

      # ── 全局始终生效的静态参数 ──────────────────────────────
      boot.kernel.sysctl = {
        "net.core.default_qdisc" = "fq";
        "net.ipv4.tcp_congestion_control" = "bbr";

        "net.ipv4.tcp_moderate_rcvbuf" = 1;
        "net.ipv4.tcp_adv_win_scale" = 2;
        "net.ipv4.tcp_window_scaling" = 1;

        "net.ipv4.tcp_tw_reuse" = 1;
        "net.ipv4.tcp_rfc1337" = 1;
        "net.ipv4.tcp_syncookies" = 1;
        "net.ipv4.ip_local_port_range" = "1024 65535";

        "net.ipv4.tcp_keepalive_time" = 60;
        "net.ipv4.tcp_keepalive_intvl" = 10;
        "net.ipv4.tcp_keepalive_probes" = 6;
        "net.ipv4.tcp_fin_timeout" = 10;

        # ── 针对高丢包极瘦流（Thin Streams）机制 ──────────────────────
        # 对于代理类的长连接且偶尔发几个包的“瘦流”，遇到丢包时不要指数级后退超时，
        # 而是线性重试。这能大幅降低操作卡顿感（例如 SSH / 网页零星请求）。
        "net.ipv4.tcp_thin_linear_timeouts" = 1;

        "net.ipv4.tcp_sack" = 1;
        "net.ipv4.tcp_timestamps" = 1;

        # ── 显式定义内核默认值（不依赖隐式默认） ───────────────────────
        # TCP Fast Open: 国内代理场景禁用 (0)，带数据的 SYN 包极易被墙或运营商丢弃/重置拖累速度
        "net.ipv4.tcp_fastopen" = 0;
        # 加速 SACK 处理：高延迟高丢包线路必须保留延迟合并（默认 1ms = 1000000 ns），
        # 否则会引发单核 CPU 100% 的 SACK 风暴。千万不能设为 0。
        "net.ipv4.tcp_comp_sack_delay_ns" = 1000000;

        "net.ipv4.tcp_ecn" = 1;
        "net.ipv4.tcp_ecn_fallback" = 1;
        "net.ipv4.tcp_early_retrans" = 4;
        "net.ipv4.tcp_frto" = 2;
        "net.ipv4.tcp_reordering" = 300;
        "net.ipv4.tcp_max_reordering" = 300;
        "net.ipv4.tcp_no_metrics_save" = 1;

        # ── MTU / 分片究极防御 (MSS Clamping) ──────────────────────────
        # ── MTU / 分片究极防御 (动态与内核探测结合) ───────────────────────
        # 恢复内核智能的 PLPMTUD (Packetization Layer PMTU Discovery, 靠 TCP 超时重传检测 MTU)
        # 不再写死 1360，由下面的 systemd 启动脚本结合物理探测下发最优雅的初始 advmss。
        "net.ipv4.tcp_mtu_probing" = 1;

        "net.ipv4.tcp_slow_start_after_idle" = 0;
        "net.ipv4.tcp_quickack" = 0; # 高延迟线路关闭 quickack，强制合包 (Delayed ACK)

        # ── 丢包容忍度极限放大 ─────────────────────────────────────────
        # tcp_recovery: 默认 1（只用 RACK）。
        # 改为 3（RACK + 开启尾部丢包的快速探测与恢复 TLP）。
        # 这意味着在遇到极高丢包时，内核敢于在连 ACK 都没收到的情况下，“盲猜”并暴力重传，
        # 让 BBR 算法在恶劣网络下表现得像 UDP 一样不屈不挠，极大增强抗压能力。
        "net.ipv4.tcp_recovery" = 3;

        # TCP 重传折叠：保持开启
        "net.ipv4.tcp_retrans_collapse" = 1;

        # ── 暴力提速机制（极限 BBR / PAWS） ──────────────────────────────
        # 让 BBR 探测周期更短，更暴力占据带宽（如果支持 tcp_bbr 模块参数）
        # FQ Pacing：放开 BBR 依赖的 FQ 发包速率硬上限，防止被网卡 qdisc 截流
        "net.core.netdev_tstamp_prequeue" = 0;
        # 禁用 tcp_autocorking，发送端绝不等待攒包，只要应用层推数据立刻打头发送（降延迟，提初速）
        "net.ipv4.tcp_autocorking" = 0;
        # 即使网卡支持 TSO，也交给内核拆包，提升小包乱序时的响应平滑度
        "net.ipv4.tcp_tso_win_divisor" = 3;

        "net.mptcp.enabled" = 1;
        "net.mptcp.checksum_enabled" = 0;
        "net.netfilter.nf_conntrack_checksum" = 0;
        "net.mptcp.scheduler" = "default";

        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
      };
    }

    # ── 启用 tuner 时应用的动态参数 ──────────────────────────────
    (lib.mkIf cfg.enable {
      boot.kernel.sysctl = {
        "net.core.rmem_max" = rmem_max;
        "net.core.wmem_max" = rmem_max;
        "net.core.rmem_default" = rmem_default;
        "net.core.wmem_default" = rmem_default;
        "net.ipv4.tcp_rmem" = "4096 ${toString rmem_default} ${toString rmem_max}";
        "net.ipv4.tcp_wmem" = "4096 ${toString rmem_default} ${toString rmem_max}";
        "net.ipv4.tcp_notsent_lowat" = notsent_lowat;
        "net.ipv4.udp_rmem_min" = 16384;
        "net.ipv4.udp_wmem_min" = 16384;

        "net.ipv4.tcp_mem" = "${toString tcp_mem_low} ${toString tcp_mem_mid} ${toString tcp_mem_high}";
        "net.ipv4.udp_mem" = "${toString udp_mem_low} ${toString udp_mem_mid} ${toString udp_mem_high}";

        "fs.file-max" = file_max;
        "fs.nr_open" = 10485760;
        "fs.pipe-max-size" = pipe_max;

        "net.core.netdev_max_backlog" = netdev_backlog;
        "net.ipv4.tcp_max_syn_backlog" = syn_backlog;
        "net.core.somaxconn" = 65535;
        "net.ipv4.tcp_max_tw_buckets" = tw_buckets;
        "net.ipv4.tcp_max_orphans" = max_orphans;

        "net.core.netdev_budget" = napi_budget;
        "net.core.netdev_budget_usecs" = 8000;
        "net.core.dev_weight" = dev_weight;
        "net.core.busy_poll" = busy_poll;
        "net.core.busy_read" = busy_poll;

        "net.core.optmem_max" = if cfg.cpus > 1 then 131072 else 65536;

        "net.netfilter.nf_conntrack_max" = conntrack_max;
        "net.netfilter.nf_conntrack_tcp_timeout_established" = 3600;
        "net.netfilter.nf_conntrack_tcp_timeout_time_wait" = 10;
        "net.netfilter.nf_conntrack_tcp_timeout_fin_wait" = 10;
        "net.netfilter.nf_conntrack_tcp_timeout_close_wait" = 10;
        "net.netfilter.nf_conntrack_tcp_timeout_close" = 5;

        "net.ipv4.tcp_syn_retries" = syn_retries;
        "net.ipv4.tcp_synack_retries" = synack_retries;
        "net.ipv4.tcp_orphan_retries" = 2;
        "net.ipv4.tcp_retries2" = tcp_retries2;

        "vm.swappiness" = vm_swappiness;
      };

      # 健壮的网卡卸载 (NIC Offloads) 开启服务
      systemd.services.enable-nic-offloads = {
        description = "Gracefully enable all possible NIC offload features (tso/gso/gro/lro/sg/rx/tx)";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        restartTriggers = [
          (builtins.hashString "sha256" config.systemd.services.enable-nic-offloads.script)
        ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = with pkgs; [
          iproute2
          ethtool
          gawk
        ];
        script = ''
          # 动态探测默认出口接口
          TARGET="1.1.1.1"
          GW_INFO=$(ip -4 route get $TARGET 2>/dev/null | head -n 1)
          IFACE=$(echo "$GW_INFO" | awk '{for(i=1;i<NF;i++) if($i=="dev") print $(i+1)}')

          if [ -z "$IFACE" ]; then
            echo "No default gateway interface found. Skipping NIC offload."
            exit 0
          fi

          echo "Found interface $IFACE. Attempting to enable offloads..."

          # 逐个尝试开启，不支持的自动跳过，不影响后续
          for feature in rx tx sg tso gso gro lro; do
            if ethtool -K "$IFACE" "$feature" on 2>/dev/null; then
               echo "Enabled $feature on $IFACE."
            else
               echo "Feature $feature not supported or failed to enable on $IFACE. Skipping."
            fi
          done

          echo "NIC offload tuning complete."
        '';
      };

      systemd.services.set-initcwnd = {
        description = "Set TCP initcwnd/initrwnd=150 and dynamic MSS on default routes";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        # Oneshot 服务不支持 reload，必须通过 restartTriggers 强制 NixOS 重启它
        restartTriggers = [
          (builtins.hashString "sha256" config.systemd.services.set-initcwnd.script)
        ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = with pkgs; [
          iproute2
          gawk
        ];
        script = ''
          # 动态探测最佳出口接口和网关
          TARGET="1.1.1.1"
          GW_INFO=$(ip -4 route get $TARGET 2>/dev/null | head -n 1)
          IFACE=$(echo "$GW_INFO" | awk '{for(i=1;i<NF;i++) if($i=="dev") print $(i+1)}')
          [ -z "$IFACE" ] && exit 0

          # 动态脚本测试探测真实可用 MTU (防分片 / 黑洞)
          BEST_PAYLOAD=1472
          for size in $(seq 1472 -10 1200); do
            if ping -I "$IFACE" -c 1 -M do -s $size -W 1 $TARGET >/dev/null 2>&1; then
              BEST_PAYLOAD=$size
              break
            fi
          done
          # IPv4 TCP MSS = MTU - 40 = Ping Payload - 12
          MSS=$((BEST_PAYLOAD - 12))

          # 获取默认路由的完整原始项
          DEF4=$(ip -4 route show default dev "$IFACE" | head -n 1)
          if [ -n "$DEF4" ]; then
            # 使用 change 之前先确保我们没有重复的核心参数
            ip route change $DEF4 initcwnd 150 initrwnd ${toString initrwnd} advmss $MSS || true
          fi

          # IPv6 探测
          TARGET6="2606:4700:4700::1111"
          GW6_INFO=$(ip -6 route get $TARGET6 2>/dev/null | head -n 1)
          IFACE6=$(echo "$GW6_INFO" | awk '{for(i=1;i<NF;i++) if($i=="dev") print $(i+1)}')
          if [ -n "$IFACE6" ]; then
            MSS6=$((MSS - 20))
            DEF6=$(ip -6 route show default dev "$IFACE6" | head -n 1)
            [ -n "$DEF6" ] && ip -6 route change $DEF6 initcwnd 150 initrwnd ${toString initrwnd} advmss $MSS6 || true
          fi

          echo "[set-initcwnd] Evaluated dynamic MSS=$MSS on $IFACE. Applied initcwnd=150 initrwnd=${toString initrwnd}."
        '';
      };
    })
  ];
}
