{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.environment.networkTune;

  # ──────────────────────────────────────────────────────────────────────────
  # § 1  辅助函数
  # ──────────────────────────────────────────────────────────────────────────
  clamp =
    lo: hi: v:
    if v < lo then
      lo
    else if v > hi then
      hi
    else
      v;

  # ──────────────────────────────────────────────────────────────────────────
  # § 2  带宽/延迟基础量（BDP）
  #
  # 使用 realBandwidth（持续可用带宽，非标称峰值）计算缓冲区，
  # 避免基于理论上限产生突发包风暴触发运营商令牌桶剪切。
  # BDP（字节）= 持续带宽(Mbps) × RTT(ms) × 125
  # ──────────────────────────────────────────────────────────────────────────
  bdp = cfg.realBandwidth * cfg.rtt * 125;

  # ──────────────────────────────────────────────────────────────────────────
  # § 3  Socket 缓冲区参数
  # ──────────────────────────────────────────────────────────────────────────

  # Socket 缓冲区上限 (rmem_max / wmem_max)
  # 取 "2×BDP" 与 "12.5% RAM" 两者的较小值，硬上限 128MB
  rmem_max_raw = bdp * 2;
  rmem_max_pct = cfg.ram * 131072; # 12.5% of RAM in bytes
  rmem_max_limit = 128 * 1024 * 1024; # 128 MB absolute ceiling
  rmem_max = clamp (16 * 1024 * 1024) rmem_max_limit (
    if rmem_max_raw < rmem_max_pct then rmem_max_raw else rmem_max_pct
  );

  # 默认缓冲区 (rmem_default / wmem_default)：取 BDP/2，夹在 [4MB, rmem_max/2]
  rmem_default_raw = bdp / 2;
  rmem_default = clamp (4 * 1024 * 1024) (rmem_max / 2) rmem_default_raw;

  # 待发送队列唤醒下限 (tcp_notsent_lowat)
  # 下限 128KB（而非 2MB），让小内存机器也能得到合理值
  notsent_lowat_raw = bdp / 4;
  notsent_lowat = clamp (128 * 1024) (rmem_max / 2) notsent_lowat_raw;

  # TCP/UDP 全局内存池（单位：页，1 页 = 4096 B）
  tcp_mem_low = cfg.ram * 256 * 15 / 100; # = ram * 38
  tcp_mem_mid = cfg.ram * 256 * 30 / 100; # = ram * 77
  tcp_mem_high_raw = cfg.ram * 256 * 50 / 100; # = ram * 128
  tcp_mem_high_bw = rmem_max * 64 / 4096; # 64× max-conn cap in pages
  tcp_mem_high = if tcp_mem_high_raw < tcp_mem_high_bw then tcp_mem_high_raw else tcp_mem_high_bw;
  udp_mem_low = tcp_mem_low / 2;
  udp_mem_mid = tcp_mem_mid / 2;
  udp_mem_high = tcp_mem_high / 2;

  # ──────────────────────────────────────────────────────────────────────────
  # § 4  连接队列参数
  # ──────────────────────────────────────────────────────────────────────────
  netdev_backlog =
    if cfg.bandwidth >= 5000 then
      500000
    else if cfg.bandwidth >= 2000 then
      300000
    else if cfg.bandwidth >= 1000 then
      100000
    else
      50000;

  # syn_backlog 与 somaxconn 保持一致，按 RAM 动态决定
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

  # ──────────────────────────────────────────────────────────────────────────
  # § 5  文件描述符 & 管道
  # ──────────────────────────────────────────────────────────────────────────
  file_max =
    if cfg.ram >= 8192 then
      2097152
    else if cfg.ram >= 2048 then
      1048576
    else
      524288;

  pipe_max = if cfg.ram >= 4096 then 8388608 else 4194304;

  # ──────────────────────────────────────────────────────────────────────────
  # § 6  CPU / NAPI 参数
  # ──────────────────────────────────────────────────────────────────────────
  napi_budget =
    if cfg.cpus == 1 then
      1200
    else if cfg.cpus <= 4 then
      2000
    else
      3000;

  dev_weight = if cfg.cpus == 1 then 128 else 256;

  busy_poll = 0; # 专用服务器可改为 50 启用忙等轮询，降低软中断延迟

  # ──────────────────────────────────────────────────────────────────────────
  # § 7  nf_conntrack
  # ──────────────────────────────────────────────────────────────────────────
  # 按 RAM 的 5% / 每个连接约 300B 估算，夹在 [65536, 2M]
  conntrack_raw = cfg.ram * 1048576 * 5 / 100 / 300;
  conntrack_max = clamp 65536 2097152 conntrack_raw;

  # ──────────────────────────────────────────────────────────────────────────
  # § 8  路由参数（initrwnd）
  #
  # 激进地基于 BDP 预留初始接收窗口。
  # BDP(包数) = bdp(字节) / 1400（MSS 估计值）
  # 取 BDP 的 1/4 作为起步，限定在 [150, 1024] 之间。
  # 1024 个 MSS（约 1.4MB）是现代内核 initrwnd 激进但安全的上限。
  # ──────────────────────────────────────────────────────────────────────────
  bdp_pkts = bdp / 1400;
  initrwnd_raw = bdp_pkts / 2; # 更激进，原来是 / 4
  initrwnd = clamp 150 2048 initrwnd_raw; # 上限放宽到 2048

  # 极其激进的初始拥塞窗口 (initcwnd)
  # 默认 10 对应 14KB，我们直接暴力给 250 (约 350KB)，让 BBR 瞬间起飞
  initcwnd = 250;

  # ──────────────────────────────────────────────────────────────────────────
  # § 9  重试次数
  # ──────────────────────────────────────────────────────────────────────────
  syn_retries =
    if cfg.highLoss && cfg.cpus == 1 then
      3
    else if cfg.highLoss then
      4
    else
      6;

  synack_retries = if cfg.highLoss then 3 else 5;
  tcp_retries2 = if cfg.cpus == 1 && cfg.ram < 1024 then 6 else 8;

  # ──────────────────────────────────────────────────────────────────────────
  # § 10  内存/Swap
  # ──────────────────────────────────────────────────────────────────────────
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
      description = "用于 BDP 和窗口计算的实际可用/持续带宽（Mbps）。默认取标称带宽的 60% 防止拥塞。";
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

    cca = lib.mkOption {
      type = lib.types.str;
      default = "bbr";
      description = ''
        TCP 拥塞控制算法。默认使用内核主线 BBRv1。
        如已加载 tcp_bbr3 内核模块，可改为 "bbr3"（最优选，激进度接近 v1 但 Startup 更平滑，
        不触发运营商令牌桶尾丢包）。
      '';
    };

    mptcpScheduler = lib.mkOption {
      type = lib.types.str;
      default = "redundant";
      description = ''
        MPTCP 子流调度器。
        - "default"：轮询（负载均衡）
        - "redundant"：在所有子流同时发送相同数据，高丢包场景抗压最强
        - "balia"：带感知调度，多接口异构场景
      '';
    };

    fqMaxrate = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = ''
        FQ 队列主动整形速率上限（Mbps）。0 表示不限制。
        建议设为实测带宽上限的 95%，例如 1Gbps 链路设为 950。
        原理：主动把发包速率卡在运营商令牌桶限速以下，永不触发硬件尾丢包，
        反比不限速的连接有更高的净吞吐。
      '';
    };
  };

  config = lib.mkMerge [
    # ════════════════════════════════════════════════════════════════════════
    # 全局静态参数：无论 enable 是否为 true 均生效
    # ════════════════════════════════════════════════════════════════════════
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

      # gai.conf：优先 IPv6，IPv4-mapped 最低优先级（标准优先级表）
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

      boot.kernel.sysctl = {
        # ── 拥塞控制 & 队列规则 ──────────────────────────────────────────
        # FQ（Fair Queuing）+ BBR 组合：FQ 负责平滑 pacing，BBR 负责速率估算。
        # FQ 的 pacing 能将 BBR 的突发包均匀分布到时间轴上，避免触发运营商令牌桶丢包。
        "net.core.default_qdisc" = "fq";
        "net.ipv4.tcp_congestion_control" = cfg.cca;

        # ── 接收窗口 & 缓冲自适应 ────────────────────────────────────────
        "net.ipv4.tcp_moderate_rcvbuf" = 1; # 允许内核自动调节接收缓冲区
        # adv_win_scale = -2：通告窗口 = 缓冲区 - overhead，最大化对端发送量
        # 旧值 2 只通告 25% 缓冲区，大带宽场景吞吐损失明显
        "net.ipv4.tcp_adv_win_scale" = -2;
        "net.ipv4.tcp_window_scaling" = 1; # 允许窗口超过 64KB（RFC 1323 必须项）

        # ── 连接管理 & 端口复用 ──────────────────────────────────────────
        "net.ipv4.tcp_tw_reuse" = 1; # TIME_WAIT 端口复用（仅出站连接）
        "net.ipv4.tcp_rfc1337" = 1; # 防 TIME_WAIT 劫持攻击
        "net.ipv4.tcp_syncookies" = 1; # SYN flood 防护
        "net.ipv4.ip_local_port_range" = "1024 65535"; # 放开出站端口范围，支持高并发

        # ── Keepalive & 超时 ─────────────────────────────────────────────
        # 60s 后开始探测，每 10s 探测一次，共 6 次 → 约 120s 检测断链
        # 解决运营商 NAT 30 分钟超时问题
        "net.ipv4.tcp_keepalive_time" = 60;
        "net.ipv4.tcp_keepalive_intvl" = 10;
        "net.ipv4.tcp_keepalive_probes" = 6;
        "net.ipv4.tcp_fin_timeout" = 10; # FIN_WAIT_2 超时，加速端口回收

        # ── 丢包恢复 ────────────────────────────────────────────────────
        "net.ipv4.tcp_sack" = 1; # 选择性确认（SACK），避免重传整个窗口
        "net.ipv4.tcp_timestamps" = 1; # TCP 时间戳（RTT 测量 & PAWS 防回绕攻击）

        # 针对高丢包极瘦流（Thin Streams）的线性超时机制：
        # 瘦流（如 SSH 信令、零星 HTTP 请求）遇到丢包时不指数级后退，
        # 而是线性重试，大幅降低操作卡顿感。
        "net.ipv4.tcp_thin_linear_timeouts" = 1;

        # tcp_recovery = 3：RACK + TLP（尾部丢包探测）
        # 遇到极高丢包时，内核敢于在没有 ACK 的情况下盲猜并暴力重传，
        # BBR 在恶劣网络下表现得像 UDP 一样不屈不挠。
        "net.ipv4.tcp_recovery" = 3;

        "net.ipv4.tcp_early_retrans" = 4; # 更积极的早期重传触发
        "net.ipv4.tcp_frto" = 2; # F-RTO：虚假超时检测（高延迟线路减少不必要重传）
        # tcp_reordering = 127：显式设为内核实际 cap 值（旧值 300 超限无效）
        # 允许接收窗口内最多 127 个乱序包后才触发快速重传
        "net.ipv4.tcp_reordering" = 127;
        # tcp_max_reordering = 300：新内核（5.x+）此上限更高，保留激进值
        "net.ipv4.tcp_max_reordering" = 300;
        "net.ipv4.tcp_no_metrics_save" = 1; # 不缓存连接历史指标，每次重新测量
        "net.ipv4.tcp_retrans_collapse" = 1; # 重传时折叠小包，减少碎片

        # ── MTU 探测 ─────────────────────────────────────────────────────
        # tcp_mtu_probing = 1：PLPMTUD 模式，遇到 ICMP black hole 时自动降低 MTU。
        # 具体 advmss 由 set-initcwnd 服务通过 ping 探测后动态下发，不写死。
        "net.ipv4.tcp_mtu_probing" = 1;

        # ── ECN（显式拥塞通知）───────────────────────────────────────────
        # TODO: ECN=0 可能在支持 ECN 的数据中心（Cloudflare/AWS/GCP）损失吞吐。
        #       BBR 将无法收到 CE 标记，只能靠丢包感知拥塞，增加 RTO 风险。
        #       建议未来改回 tcp_ecn = 1 或 2（与对端协商）并观察实际效果。
        "net.ipv4.tcp_ecn" = 0;
        "net.ipv4.tcp_ecn_fallback" = 1; # 即使请求 ECN，对端不支持时自动 fallback

        # ── 发包行为优化 ─────────────────────────────────────────────────
        "net.ipv4.tcp_slow_start_after_idle" = 0; # 空闲后不重置拥塞窗口，保持满速
        # tcp_fastopen = 0：国内代理场景关闭，带数据 SYN 包极易被运营商/GFW 丢弃
        "net.ipv4.tcp_fastopen" = 0;
        # SACK 合并延迟 1ms：防止高丢包高延迟时单核 100% 的 SACK 风暴。绝不能设为 0。
        "net.ipv4.tcp_comp_sack_delay_ns" = 1000000;
        # tcp_autocorking = 0：关闭内核自动合包，有数据立刻发，降低初速延迟
        "net.ipv4.tcp_autocorking" = 0;
        # tso_win_divisor = 3：即使网卡支持 TSO，也交由内核拆包，
        # 提升小包乱序时的响应平滑度（与 FQ pacing 配合）
        "net.ipv4.tcp_tso_win_divisor" = 3;
        # tcp_quickack = 1：开启全局 quickack (不延迟 ACK)，配合 BBR 极速测量带宽
        # 牺牲一点上行带宽，换取 10 倍速的 RTT 测量和拥塞窗口增长
        "net.ipv4.tcp_quickack" = 1;

        # ── pacing 激进优化 (配合 BBR / FQ) ──────────────────────────────
        # 允许内核缓冲大量待发 pacing 数据，避免发送端应用层 block
        "net.ipv4.tcp_pacing_ss_ratio" = 200; # Slow Start 时 pacing_rate = 200% cwnd
        "net.ipv4.tcp_pacing_ca_ratio" = 120; # 拥塞避免时 pacing_rate = 120% cwnd

        # ── MPTCP（多路径 TCP）──────────────────────────────────────────
        "net.mptcp.enabled" = 1;
        "net.mptcp.checksum_enabled" = 0; # 关闭 MPTCP 层校验和，减少 CPU 开销
        "net.mptcp.scheduler" = cfg.mptcpScheduler;

        # ── IP 转发 ──────────────────────────────────────────────────────
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;

        # ── Conntrack ────────────────────────────────────────────────────
        "net.netfilter.nf_conntrack_checksum" = 0; # 关闭 conntrack 校验和验证，减少 CPU 开销
      };
    }

    # ════════════════════════════════════════════════════════════════════════
    # 动态参数：仅在 enable = true 时生效
    # ════════════════════════════════════════════════════════════════════════
    (lib.mkIf cfg.enable {
      boot.kernel.sysctl = {
        # ── Socket 缓冲区（动态，基于 BDP × RAM）────────────────────────
        "net.core.rmem_max" = rmem_max;
        "net.core.wmem_max" = rmem_max;
        "net.core.rmem_default" = rmem_default;
        "net.core.wmem_default" = rmem_default;
        "net.ipv4.tcp_rmem" = "4096 ${toString rmem_default} ${toString rmem_max}";
        "net.ipv4.tcp_wmem" = "4096 ${toString rmem_default} ${toString rmem_max}";
        "net.ipv4.tcp_notsent_lowat" = notsent_lowat;
        "net.ipv4.udp_rmem_min" = 16384;
        "net.ipv4.udp_wmem_min" = 16384;

        # ── TCP/UDP 全局内存池（单位：页）────────────────────────────────
        "net.ipv4.tcp_mem" = "${toString tcp_mem_low} ${toString tcp_mem_mid} ${toString tcp_mem_high}";
        "net.ipv4.udp_mem" = "${toString udp_mem_low} ${toString udp_mem_mid} ${toString udp_mem_high}";

        # ── 文件描述符 & 管道 ────────────────────────────────────────────
        "fs.file-max" = file_max;
        "fs.nr_open" = 10485760;
        "fs.pipe-max-size" = pipe_max;

        # ── 连接队列（动态，基于带宽和内存）─────────────────────────────
        "net.core.netdev_max_backlog" = netdev_backlog;
        "net.ipv4.tcp_max_syn_backlog" = syn_backlog;
        # somaxconn 与 syn_backlog 保持一致，确保全连接队列不成为瓶颈
        "net.core.somaxconn" = syn_backlog;
        "net.ipv4.tcp_max_tw_buckets" = tw_buckets;
        "net.ipv4.tcp_max_orphans" = max_orphans;

        # ── CPU & NAPI 批处理 ────────────────────────────────────────────
        "net.core.netdev_budget" = napi_budget;
        "net.core.netdev_budget_usecs" = 8000;
        "net.core.dev_weight" = dev_weight;
        "net.core.busy_poll" = busy_poll;
        "net.core.busy_read" = busy_poll;

        # optmem_max：每个 socket 的辅助内存上限（cmsg、过滤器等）
        "net.core.optmem_max" = if cfg.cpus > 1 then 131072 else 65536;

        # ── Conntrack 超时 ────────────────────────────────────────────────
        "net.netfilter.nf_conntrack_max" = conntrack_max;
        "net.netfilter.nf_conntrack_tcp_timeout_established" = 3600;
        "net.netfilter.nf_conntrack_tcp_timeout_time_wait" = 10;
        "net.netfilter.nf_conntrack_tcp_timeout_fin_wait" = 10;
        "net.netfilter.nf_conntrack_tcp_timeout_close_wait" = 10;
        "net.netfilter.nf_conntrack_tcp_timeout_close" = 5;

        # ── 重试次数（动态，基于丢包情况和资源）──────────────────────────
        "net.ipv4.tcp_syn_retries" = syn_retries;
        "net.ipv4.tcp_synack_retries" = synack_retries;
        "net.ipv4.tcp_orphan_retries" = 2;
        "net.ipv4.tcp_retries2" = tcp_retries2;

        # ── 内存/Swap ────────────────────────────────────────────────────
        "vm.swappiness" = vm_swappiness;
      };

      # ── 服务一：健壮的网卡卸载（NIC Offloads）─────────────────────────
      # 必须在 set-initcwnd 之前完成，否则两个服务会并发探测接口产生竞争。
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
          TARGET="1.1.1.1"
          GW_INFO=$(ip -4 route get $TARGET 2>/dev/null | head -n 1)
          IFACE=$(echo "$GW_INFO" | awk '{for(i=1;i<NF;i++) if($i=="dev") print $(i+1)}')

          if [ -z "$IFACE" ]; then
            echo "No default gateway interface found. Skipping NIC offload."
            exit 0
          fi

          echo "Found interface $IFACE. Attempting to enable offloads..."

          # 逐个尝试开启，不支持的自动跳过，不中断后续
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

      # ── 服务二：TCP initcwnd/initrwnd & 动态 MSS ───────────────────────
      # 必须在 enable-nic-offloads 之后执行，避免并发接口探测冲突。
      systemd.services.set-initcwnd = {
        description = "Set TCP initcwnd/initrwnd and dynamic MSS on default routes";
        # 关键：强依赖 enable-nic-offloads，确保顺序执行，消除竞争
        after = [
          "network-online.target"
          "enable-nic-offloads.service"
        ];
        requires = [ "enable-nic-offloads.service" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        restartTriggers = [
          (builtins.hashString "sha256" config.systemd.services.set-initcwnd.script)
        ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = with pkgs; [
          iproute2
          iputils # ping
          gawk
        ];
        script = ''
          TARGET="1.1.1.1"
          GW_INFO=$(ip -4 route get $TARGET 2>/dev/null | head -n 1)
          IFACE=$(echo "$GW_INFO" | awk '{for(i=1;i<NF;i++) if($i=="dev") print $(i+1)}')
          [ -z "$IFACE" ] && exit 0

          # 探测真实可用 MTU（防止 ICMP black hole 导致分片/路径 MTU 黑洞）
          # 推导：ping -s SIZE 发出的 ICMP payload = SIZE 字节
          #       ICMP header(8) + IP header(20) + SIZE = 物理帧大小
          #       SIZE=1472 → 帧=1500 → 恰好填满标准 MTU
          #       TCP MSS = MTU - IP header(20) - TCP header(20)
          #               = (SIZE + 28) - 40 = SIZE - 12
          #       所以：MSS = BEST_PAYLOAD - 12
          BEST_PAYLOAD=1472
          for size in $(seq 1472 -10 1200); do
            if ping -I "$IFACE" -c 1 -M do -s $size -W 1 $TARGET >/dev/null 2>&1; then
              BEST_PAYLOAD=$size
              break
            fi
          done
          MSS=$((BEST_PAYLOAD - 12))

          # 应用 IPv4 默认路由：initcwnd=250，initrwnd=${toString initrwnd}，advmss=$MSS
          DEF4=$(ip -4 route show default dev "$IFACE" | head -n 1)
          if [ -n "$DEF4" ]; then
            ip route change $DEF4 initcwnd ${toString initcwnd} initrwnd ${toString initrwnd} advmss $MSS || true
          fi

          # IPv6：IPv6 头比 IPv4 多 20B，MSS 相应减少 20
          TARGET6="2606:4700:4700::1111"
          GW6_INFO=$(ip -6 route get $TARGET6 2>/dev/null | head -n 1)
          IFACE6=$(echo "$GW6_INFO" | awk '{for(i=1;i<NF;i++) if($i=="dev") print $(i+1)}')
          if [ -n "$IFACE6" ]; then
            MSS6=$((MSS - 20))
            DEF6=$(ip -6 route show default dev "$IFACE6" | head -n 1)
            [ -n "$DEF6" ] && ip -6 route change $DEF6 initcwnd ${toString initcwnd} initrwnd ${toString initrwnd} advmss $MSS6 || true
          fi

          echo "[set-initcwnd] iface=$IFACE MSS=$MSS initcwnd=${toString initcwnd} initrwnd=${toString initrwnd}"
        '';
      };

      # ── 服务三：FQ Pacing 主动整形（可选，fqMaxrate > 0 时生效）────────
      # 原理：主动将出口速率限制在运营商带宽上限的 ~95%，
      #        FQ 将包均匀分布到时间轴，永不触发运营商交换机硬件尾丢包，
      #        净吞吐反比不限速 + 频繁 RTO 重传的连接更高。
      systemd.services.set-fq-pacing = lib.mkIf (cfg.fqMaxrate > 0) {
        description = "Apply FQ pacing rate limit to smooth out burst and avoid token bucket drops";
        after = [
          "network-online.target"
          "enable-nic-offloads.service"
        ];
        requires = [ "enable-nic-offloads.service" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        restartTriggers = [
          (builtins.hashString "sha256" config.systemd.services.set-fq-pacing.script)
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
          TARGET="1.1.1.1"
          GW_INFO=$(ip -4 route get $TARGET 2>/dev/null | head -n 1)
          IFACE=$(echo "$GW_INFO" | awk '{for(i=1;i<NF;i++) if($i=="dev") print $(i+1)}')
          [ -z "$IFACE" ] && exit 0

          # 替换（replace）而非添加（add），确保幂等，重启服务不会叠加规则
          tc qdisc replace dev "$IFACE" root fq maxrate ${toString cfg.fqMaxrate}mbit
          echo "[set-fq-pacing] Applied fq maxrate=${toString cfg.fqMaxrate}mbit on $IFACE"
        '';
      };
      # 10. 内核与网络调优
      # 使用 XanMod 核心以获得最新的 BBR 优化 (包括 v3) 和更好的网络吞吐
      boot.kernelPackages = pkgs.linuxPackages_xanmod_latest;
    })
  ];
}
