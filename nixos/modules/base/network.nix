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
  # BDP（字节）= 带宽(Mbps) × RTT(ms) × 125
  # 单一激进策略：直接按接近标称带宽估算 BDP，上限更高。
  # ──────────────────────────────────────────────────────────────────────────
  bdpBasisBandwidth = builtins.floor (cfg.bandwidth * 90 / 100);
  bdp = bdpBasisBandwidth * cfg.rtt * 125;
  ramBytes = cfg.ram * 1024 * 1024;

  # ──────────────────────────────────────────────────────────────────────────
  # § 3  Socket 缓冲区参数
  # ──────────────────────────────────────────────────────────────────────────

  # Socket 缓冲区上限 (rmem_max / wmem_max)
  # 取 "2×BDP" 与 "12.5% RAM" 两者的较小值，硬上限 128MB
  rmem_max_raw = bdp * 2;
  rmem_max_pct = if isBerserk then ramBytes * 70 / 100 else ramBytes * 12 / 100;
  rmem_max = clamp rmemMinFloor rmemMaxLimit (
    if rmem_max_raw < rmem_max_pct then rmem_max_raw else rmem_max_pct
  );

  # 默认缓冲区 (rmem_default / wmem_default)：取 BDP/2，夹在 [4MB, rmem_max/2]
  rmem_default_raw = bdp / 2;
  rmem_default = clamp rmemDefaultFloor (
    rmem_max * rmemDefaultCeilFactor / rmemDefaultCeilDiv
  ) rmem_default_raw;

  # 待发送队列唤醒下限 (tcp_notsent_lowat)
  # 下限 128KB（而非 2MB），让小内存机器也能得到合理值
  notsent_lowat_raw = bdp / 4;
  notsent_lowat = clamp (128 * 1024) notsentLowatCap notsent_lowat_raw;

  # TCP/UDP 全局内存池（单位：页，1 页 = 4096 B）
  # 提高内存利用比例：让小内存机器也敢于把更多内存给网络栈。
  tcp_mem_low = cfg.ram * 256 * 18 / 100;
  tcp_mem_mid = cfg.ram * 256 * 38 / 100;
  tcp_mem_high_raw = cfg.ram * 256 * tcpMemHighPct / 100;
  tcp_mem_high_bw = rmem_max * 64 / 4096; # 64× max-conn cap in pages
  tcp_mem_high = if tcp_mem_high_raw < tcp_mem_high_bw then tcp_mem_high_raw else tcp_mem_high_bw;
  udp_mem_low = tcp_mem_low / 2;
  udp_mem_mid = tcp_mem_mid / 2;
  udp_mem_high = tcp_mem_high / 2;

  tcpMemHighPct = if isBerserk then clamp 80 97 (78 + cfg.cpus * 2 + cfg.realBandwidth / 600) else 50;

  # ──────────────────────────────────────────────────────────────────────────
  # § 4  稳定连接预算（核心）
  # ──────────────────────────────────────────────────────────────────────────
  # 保持单一高性能配置，不再区分 profile 档位。
  isBerserk = true;
  # 既然引用此配置的均为 VPS，强制开启 VPS 模式
  isVpsMode = true;

  # Profile constants: centralize tuning knobs for readability/maintainability.
  rmemMaxLimit = if isBerserk then ramBytes * 85 / 100 else ramBytes * 20 / 100;
  # 如果是 VPS 且内存小，保命优先，下限降低但保持合理比例
  rmemMinFloor =
    if isVpsMode then
      ramBytes * 15 / 100
    else
      (if isBerserk then ramBytes * 25 / 100 else 16 * 1024 * 1024);
  rmemDefaultFloor = if isBerserk then ramBytes * 10 / 100 else 4 * 1024 * 1024;
  rmemDefaultCeilFactor = if isBerserk then 19 else 2;
  rmemDefaultCeilDiv = if isBerserk then 20 else 2;
  notsentLowatCap = if isBerserk then ramBytes * 20 / 100 else rmem_max / 2;

  connBudgetRamFactor = if isBerserk then 280 else 10;
  connBudgetCpuFactor = if isBerserk then 150000 else 7000;
  connBudgetBwFactor = if isBerserk then 380 else 24;
  stableConnCap =
    if isBerserk then lib.max 600000 (cfg.ram * cfg.cpus * cfg.realBandwidth * 20) else 600000;
  netdevBacklogBwFactor = if isBerserk then 1600 else 110;
  netdevBacklogCpuFactor = if isBerserk then 180000 else 20000;
  netdevBacklogCap =
    if isBerserk then lib.max 1200000 (cfg.realBandwidth * 3000 + cfg.cpus * 250000) else 1200000;
  synBacklogCap = if isBerserk then lib.max 1048576 (cfg.ram * cfg.cpus * 4096) else 1048576;
  twBucketsCap = if isBerserk then lib.max 4000000 (cfg.ram * cfg.cpus * 50000) else 4000000;
  maxOrphansCap = if isBerserk then lib.max 524288 (cfg.ram * cfg.cpus * 4096) else 524288;
  fileMaxCap = if isBerserk then lib.max 6291456 (cfg.ram * cfg.cpus * 24000) else 6291456;
  conntrackCap = if isBerserk then lib.max 4194304 (cfg.ram * cfg.cpus * 16000) else 4194304;

  connBudgetRam = cfg.ram * connBudgetRamFactor;
  connBudgetCpu = cfg.cpus * connBudgetCpuFactor;
  connBudgetBw = cfg.realBandwidth * connBudgetBwFactor;
  stableConnBudget = clamp 4096 stableConnCap (
    lib.min connBudgetRam (lib.min connBudgetCpu connBudgetBw)
  );

  # ──────────────────────────────────────────────────────────────────────────
  # § 5  连接队列参数（由稳定连接预算推导）
  # ──────────────────────────────────────────────────────────────────────────
  netdev_backlog = clamp 50000 netdevBacklogCap (
    (cfg.realBandwidth * netdevBacklogBwFactor) + (cfg.cpus * netdevBacklogCpuFactor)
  );
  syn_backlog = clamp 16384 synBacklogCap (stableConnBudget * 4 / 5);
  tw_buckets = clamp 200000 twBucketsCap (stableConnBudget * 12);
  max_orphans = clamp 8192 maxOrphansCap (stableConnBudget / 4);

  # ──────────────────────────────────────────────────────────────────────────
  # § 6  文件描述符 & 管道
  # ──────────────────────────────────────────────────────────────────────────
  file_max = clamp 524288 fileMaxCap (stableConnBudget * 10);

  pipe_max = if cfg.ram >= 4096 then 8388608 else 4194304;

  # ──────────────────────────────────────────────────────────────────────────
  # § 7  CPU / NAPI 参数
  # ──────────────────────────────────────────────────────────────────────────
  napi_budget =
    if isBerserk then
      if cfg.cpus == 1 then
        9000
      else if cfg.cpus <= 4 then
        12800
      else
        16800
    else if cfg.cpus == 1 then
      1200
    else if cfg.cpus <= 4 then
      2000
    else
      3000;

  dev_weight =
    if isBerserk then
      if cfg.cpus == 1 then (if isVpsMode then 512 else 1024) else 2048
    else if cfg.cpus == 1 then
      128
    else
      256;

  # 单核主机上 busy-poll 过高会放大 CPU 抢占与抖动，适度下调。
  # 对于 VPS 且单核，busy_poll 设为 0 以防由于宿主机调度延迟导致的 Guest CPU 假死。
  busy_poll = if isBerserk then if cfg.cpus == 1 then (if isVpsMode then 0 else 50) else 150 else 0;
  # 单核主机避免 NAPI 长时间占满一个调度周期，降低 PSI 抖动。
  netdev_budget_usecs =
    if isBerserk then if cfg.cpus == 1 then (if isVpsMode then 30000 else 45000) else 90000 else 8000;
  rpsSockFlowEntries = if isBerserk then 2097152 else 65536;

  # ──────────────────────────────────────────────────────────────────────────
  # § 8  nf_conntrack
  # ──────────────────────────────────────────────────────────────────────────
  conntrack_max = clamp 65536 conntrackCap (stableConnBudget * 5 / 2);

  # ──────────────────────────────────────────────────────────────────────────
  # § 9  路由参数（initrwnd / initcwnd）
  # ──────────────────────────────────────────────────────────────────────────
  bdp_pkts = bdp / 1400;
  # initcwnd：回到“高起速”基线（2400）并按链路/CPU继续上调。
  # 单位换算：pkt ~= MSS(1460B)
  firstRttPayloadBytes = clamp (256 * 1024) (6 * 1024 * 1024) (bdp * 65 / 100);
  initcwnd_from_first_rtt = (firstRttPayloadBytes + 1459) / 1460;
  initcwnd_from_bdp = bdp_pkts;
  initcwnd_from_cpu = cfg.cpus * 320;
  initcwnd_floor = if cfg.highLoss then 150 else 120;
  initcwnd_bw_boost =
    if cfg.bandwidth >= 5000 then
      700
    else if cfg.bandwidth >= 2000 then
      500
    else if cfg.bandwidth >= 1000 then
      300
    else
      120;
  initcwnd_rtt_boost =
    if cfg.rtt >= 220 then
      280
    else if cfg.rtt >= 160 then
      180
    else if cfg.rtt >= 100 then
      90
    else
      0;
  initcwnd_raw = lib.max (initcwnd_floor + initcwnd_bw_boost) (
    lib.max initcwnd_from_first_rtt (lib.max initcwnd_from_bdp initcwnd_from_cpu)
  );
  initrwnd_raw = bdp_pkts * 3 / 5;
  # 单核主机限制接收窗口初值，避免首轮突发放大软中断压力。
  initrwnd = clamp 300 (if cfg.cpus == 1 then 4096 else 16384) initrwnd_raw;
  initcwndCap = lib.max 4096 (bdp_pkts * 2 + cfg.cpus * 1024 + cfg.realBandwidth / 2);
  # 单核主机限制初始拥塞窗口，减轻启动瞬时 CPU 峰值与排队压力。
  initcwnd = clamp 1024 (if cfg.cpus == 1 then lib.min 6144 initcwndCap else initcwndCap) (
    initcwnd_raw + initcwnd_rtt_boost
  );

  # BBRv1 + fq 的慢启动 pacing：回到高攻势区间，并按链路动态。
  pacingSsBase = if cfg.highLoss then 900 else 940;
  pacingSsBwBoost =
    if cfg.realBandwidth >= 5000 then
      200
    else if cfg.realBandwidth >= 2000 then
      170
    else if cfg.realBandwidth >= 1000 then
      120
    else
      80;
  pacingSsRttPenalty =
    if cfg.rtt >= 260 then
      70
    else if cfg.rtt >= 180 then
      45
    else if cfg.rtt >= 120 then
      20
    else
      0;
  pacingSsMin = clamp 220 900 (260 + cfg.realBandwidth / 8 - cfg.rtt / 2);
  pacingSsMax = clamp (pacingSsMin + 60) 980 (pacingSsMin + 220 + cfg.cpus * 40);
  pacingSsRatio = clamp pacingSsMin pacingSsMax (pacingSsBase + pacingSsBwBoost - pacingSsRttPenalty);
  pacingCaRatio = clamp 120 360 (pacingSsRatio * 28 / 100);
  # 内核对 pacing ratio 的硬边界（只能保留这个最小约束）
  pacingSsKernelMax = lib.min 1000 (pacingSsMax + 40);
  pacingSsKernelMin = 100;

  tcpLimitOutputBytes = clamp (512 * 1024) (ramBytes * 20 / 100) (bdp * 3 / 2 + 4 * 1024 * 1024);

  # ──────────────────────────────────────────────────────────────────────────
  # § 10  重试次数
  # ──────────────────────────────────────────────────────────────────────────
  syn_retries = if cfg.highLoss then 6 else 5;
  synack_retries = if cfg.highLoss then 5 else 4;
  tcp_retries2 = if cfg.highLoss then 15 else 10;

  # ──────────────────────────────────────────────────────────────────────────
  # § 11  内存/Swap
  # ──────────────────────────────────────────────────────────────────────────
  vm_swappiness = if cfg.ram >= 8192 then 5 else 1;

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

    profile = lib.mkOption {
      type = lib.types.str;
      default = "aggressive";
      description = "兼容旧配置字段，当前实现固定为单一激进策略，不再分档。";
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
      default = "bbrv1";
      description = "TCP 拥塞控制算法（如 bbrv1 / bbr / cubic）。";
    };

    mptcpScheduler = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = ''
        MPTCP 子流调度器。
        - "default"：轮询（负载均衡）
        - "redundant"：在所有子流同时发送相同数据，高丢包场景抗压最强
        - "balia"：带感知调度，多接口异构场景
      '';
    };

    fqMaxrate = lib.mkOption {
      type = lib.types.int;
      # 默认关闭整形，优先追求峰值；如需稳态可按主机覆写。
      default = 0;
      description = ''
        FQ 队列主动整形速率上限（Mbps）。
        默认自动取 realBandwidth × 95%。设为 0 则关闭整形。
        原理：主动把发包速率卡在运营商令牌桶限速以下，永不触发硬件尾丢包，
        净吞吐反比不限速 + 频繁 RTO 重传的连接更高。
      '';
    };

    qosProbe = {
      enable = lib.mkEnableOption "QoS closed-loop controller" // {
        default = false;
      };

      intervalSec = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = "被动指标采样周期（秒）。建议 2-5 秒用于快速反惩罚。";
      };

      activeProbeEvery = lib.mkOption {
        type = lib.types.int;
        default = 15;
        description = "主动探测间隔（秒）。";
      };

      maxOverheadPct = lib.mkOption {
        type = lib.types.float;
        default = 0.5;
        description = "主动探测流量占比上限（百分比）。";
      };

      probeTarget = lib.mkOption {
        type = lib.types.str;
        default = "1.1.1.1";
        description = "主动探测目的地址。";
      };

    };

    cpuBerserk = {
      enable = lib.mkEnableOption "aggressive CPU frequency and boost tuning" // {
        default = true;
      };

      pinMaxFreq = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "将各 policy 的最小频率直接钉到最大频率，追求最低升频延迟。";
      };

      cpuidleDisableLatencyUs = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "禁用 exit latency >= 此阈值(us) 的 C-state。值越小越激进。";
      };

      holdDmaLatency = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "保持 /dev/cpu_dma_latency=0，强制低延迟唤醒（功耗更高）。";
      };

      rebalanceIRQs = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "在禁用 irqbalance 场景下手动轮询分配 IRQ 到多核，提高并行处理能力。";
      };

      disableSchedulerAutogroup = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "关闭 CFS autogroup，减少交互式策略对网络负载调度的干扰。";
      };

      disableTimerMigration = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "关闭 timer migration，减少跨核迁移抖动并加速本核响应。";
      };

      boostKernelNetThreads = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "提升 ksoftirqd/irq 线程调度优先级，抢占式优先处理网络包。";
      };
    };

    stableConnBudget = lib.mkOption {
      type = lib.types.int;
      readOnly = true;
      description = "由 CPU/RAM/BW 推导得到的稳定连接预算。";
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
        # tcp_reordering = 64：允许最多 64 个乱序包后再触发快速重传。
        # 旧值 127 是内核 cap，但在高丢包场景下乱序误判过多，
        # 会导致不必要的快速重传风暴；64 是高丢包国际链路的稳定平衡点。
        "net.ipv4.tcp_reordering" = 64;
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
        # SACK 合并延迟 1ms：防止高丢包高延迟时单核 100% 的 SACK 风暴。绝不能设为 0。
        "net.ipv4.tcp_comp_sack_delay_ns" = 1000000;
        # tcp_autocorking = 0：关闭内核自动合包，有数据立刻发，降低初速延迟
        "net.ipv4.tcp_autocorking" = 0;
        # tcp_quickack = 1：开启全局 quickack (不延迟 ACK)，配合 BBR 极速测量带宽
        # 牺牲一点上行带宽，换取 10 倍速的 RTT 测量和拥塞窗口增长
        "net.ipv4.tcp_quickack" = 1;

        # ── 稳定性 / 抗 GFW RST 注入 ────────────────────────────────────
        # tcp_challenge_ack_limit：每秒允许发送的 challenge ACK 上限。
        # GFW 会伪造 RST/ACK 包触发连接重置，低上限（默认旧版 100）容易被攻破。
        # 设为 1000，提高抗 RST 注入能力，不影响正常连接重置。
        "net.ipv4.tcp_challenge_ack_limit" = 1000;

        # ── 运营商 QoS 规避：TTL 伪装 ───────────────────────────────────
        # Linux 默认 TTL=64，是运营商 DPI 识别 Linux 服务器流量的特征之一。
        # 改为 128（Windows / CDN 特征值），让限速策略难以精准命中本机流量。
        # 副作用：traceroute 显示跳数多 64，正常通信完全不受影响。
        "net.ipv4.ip_default_ttl" = 128;

        # ── 接收时间戳预队列 ─────────────────────────────────────────────
        # 禁用软中断前的包时间戳记录，减少接收路径 overhead，降低接收延迟。
        "net.core.netdev_tstamp_prequeue" = 0;

        # ── pacing 激进优化 (配合 BBR / FQ) ──────────────────────────────
        # 允许内核缓冲大量待发 pacing 数据，避免发送端应用层 block
        # 暴力竞争模式：Slow Start 快速抢占，CA 阶段保持压制。
        "net.ipv4.tcp_pacing_ss_ratio" = pacingSsRatio;
        "net.ipv4.tcp_pacing_ca_ratio" = pacingCaRatio;

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
    {
      # 固定 XanMod 内核 + 外置 bbrv1 模块，避免每次重编整内核。
      boot.kernelPackages = lib.mkForce pkgs.linuxPackages_xanmod_latest;
      boot.extraModulePackages = lib.mkIf (cfg.cca == "bbrv1") [
        (config.boot.kernelPackages.callPackage ../../../pkgs/bbrv1-kmod { })
      ];
      boot.kernelModules = lib.mkIf (cfg.cca == "bbrv1") [ "tcp_bbrv1" ];
    }

    # ════════════════════════════════════════════════════════════════════════
    # 动态参数：仅在 enable = true 时生效
    # ════════════════════════════════════════════════════════════════════════
    (lib.mkIf cfg.enable {
      environment.networkTune.stableConnBudget = stableConnBudget;

      boot.kernel.sysctl = {
        # ── Socket 缓冲区（动态，基于 BDP × RAM）────────────────────────
        "net.core.rmem_max" = rmem_max;
        "net.core.wmem_max" = rmem_max;
        "net.core.rmem_default" = rmem_default;
        "net.core.wmem_default" = rmem_default;
        "net.ipv4.tcp_rmem" = "4096 ${toString rmem_default} ${toString rmem_max}";
        "net.ipv4.tcp_wmem" = "4096 ${toString rmem_default} ${toString rmem_max}";
        "net.ipv4.tcp_notsent_lowat" = notsent_lowat;
        # berserk: TFO 打开 client+server，提升短连接首包速度
        "net.ipv4.tcp_fastopen" = if isBerserk then 3 else 0;
        # 提升每连接发送积压上限：优先爆发爬坡，反惩罚阶段再由闭环轻收敛。
        "net.ipv4.tcp_limit_output_bytes" = if isBerserk then tcpLimitOutputBytes else 262144;
        # 控制单次 TSO 聚合突发：berserk 更偏向爆发，steady 更偏向时延
        "net.ipv4.tcp_tso_win_divisor" = if isBerserk then 1 else 4;
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
        "net.core.netdev_budget_usecs" = netdev_budget_usecs;
        "net.core.dev_weight" = dev_weight;
        "net.core.busy_poll" = busy_poll;
        "net.core.busy_read" = busy_poll;
        "net.core.rps_sock_flow_entries" = rpsSockFlowEntries;

        # optmem_max：每个 socket 的辅助内存上限（cmsg、过滤器等）
        "net.core.optmem_max" = if cfg.cpus > 1 then 524288 else 262144;

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

      # ── 服务一补充：RPS/XPS 多核分流（提高 CPU 使用率与并行包处理）────
      systemd.services.tune-rps-xps = {
        description = "Aggressive RPS/XPS fan-out for multi-core packet processing";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = with pkgs; [
          iproute2
          coreutils
          gawk
        ];
        script = ''
          set -euo pipefail
          TARGET="1.1.1.1"
          GW_INFO=$(ip -4 route get "$TARGET" 2>/dev/null | head -n 1)
          IFACE=$(echo "$GW_INFO" | awk '{for(i=1;i<NF;i++) if($i=="dev") print $(i+1)}')
          [ -z "$IFACE" ] && exit 0

          ncpu=$(nproc 2>/dev/null || echo 1)
          if [ "$ncpu" -ge 64 ]; then
            mask="ffffffff,ffffffff"
          elif [ "$ncpu" -ge 32 ]; then
            mask="ffffffff"
          else
            mask=$(printf "%x" $(( (1 << ncpu) - 1 )))
          fi

          flow_cnt=$(( ${toString rpsSockFlowEntries} / ncpu ))
          [ "$flow_cnt" -lt 1024 ] && flow_cnt=1024

          for q in /sys/class/net/"$IFACE"/queues/rx-*; do
            [ -d "$q" ] || continue
            [ -w "$q/rps_cpus" ] && echo "$mask" > "$q/rps_cpus" || true
            [ -w "$q/rps_flow_cnt" ] && echo "$flow_cnt" > "$q/rps_flow_cnt" || true
          done

          for q in /sys/class/net/"$IFACE"/queues/tx-*; do
            [ -d "$q" ] || continue
            [ -w "$q/xps_cpus" ] && echo "$mask" > "$q/xps_cpus" || true
          done

          echo "[tune-rps-xps] iface=$IFACE ncpu=$ncpu mask=$mask flow_cnt=$flow_cnt"
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

          # 应用 IPv4 默认路由：initcwnd=${toString initcwnd}，initrwnd=${toString initrwnd}，advmss=$MSS
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

          # 替换（replace）而非添加（add），确保幂等，重启服务不会叠加规则。
          # flow_limit 200：允许单个 FQ flow 积压 200 个包（默认 100）。
          # kernel-relay 场景所有转发流量 src IP 相同，FQ 视为同一 flow，
          # 提高上限防止合法转发流量被 FQ 自身限速。
          tc qdisc replace dev "$IFACE" root fq maxrate ${toString cfg.fqMaxrate}mbit flow_limit 200 quantum 12000 initial_quantum 65536
          echo "[set-fq-pacing] Applied fq maxrate=${toString cfg.fqMaxrate}mbit flow_limit=200 quantum=12000 on $IFACE"
        '';
      };

      # ── 服务四：QoS 反制闭环（持续探测 + 自动切档）──────────────────────
      systemd.services.network-qos-controller = lib.mkIf cfg.qosProbe.enable {
        description = "QoS closed-loop controller (GREEN/YELLOW/RED)";
        after = [
          "network-online.target"
          "set-initcwnd.service"
        ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        restartTriggers = [
          (builtins.hashString "sha256" config.systemd.services.network-qos-controller.script)
        ];

        serviceConfig = {
          Type = "oneshot";
          RuntimeDirectory = "network-qos";
        };
        path = with pkgs; [
          iproute2
          iputils
          procps
          coreutils
          gawk
          gnugrep
          nftables
        ];
        script = ''
                    set -euo pipefail

                    STATE_DIR="/run/network-qos"
                    mkdir -p "$STATE_DIR"

                    TARGET="${cfg.qosProbe.probeTarget}"
                    SAMPLE_INTERVAL=${toString cfg.qosProbe.intervalSec}
                    ACTIVE_EVERY=$(( ${toString cfg.qosProbe.activeProbeEvery} / SAMPLE_INTERVAL ))
                    [ "$ACTIVE_EVERY" -lt 1 ] && ACTIVE_EVERY=1
                    IFACE=$(ip -4 route get "$TARGET" 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}')
                    [ -z "$IFACE" ] && exit 0

                    read_tcp_ext() {
                      local key="$1"
                      awk -v key="$key" '
                        /^TcpExt:/{
                          if (!header_done) {
                            for (i=1; i<=NF; i++) hdr[i]=$i
                            header_done=1
                          } else {
                            for (i=1; i<=NF; i++) if (hdr[i]==key) { print $i; exit }
                          }
                        }
                      ' /proc/net/netstat
                    }

                    now=$(date +%s)
                    prev_now=$(cat "$STATE_DIR/prev_now" 2>/dev/null || echo "$now")
                    elapsed=$(( now - prev_now ))
                    [ "$elapsed" -le 0 ] && elapsed=$SAMPLE_INTERVAL

                    retrans=$(read_tcp_ext TCPRetransSegs)
                    passive=$(read_tcp_ext PassiveOpens)
                    qdisc_drop=$(tc -s qdisc show dev "$IFACE" 2>/dev/null | awk '/dropped/ {for(i=1;i<=NF;i++) if($i=="dropped"){gsub(",","",$(i+1)); sum+=$(i+1)}} END{print sum+0}')
                    softnet_drop=$(awk '{sum += strtonum("0x"$2)} END{print sum+0}' /proc/net/softnet_stat)
                    tx_bytes=$(cat "/sys/class/net/$IFACE/statistics/tx_bytes" 2>/dev/null || echo 0)
                    conn_count=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0)
                    conn_max=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 1)
                    mem_psi=$(awk '/^some/ {for(i=1;i<=NF;i++) if($i ~ /^avg10=/){split($i,a,"="); print int(a[2]+0); exit}}' /proc/pressure/memory 2>/dev/null || echo 0)
                    io_psi=$(awk '/^some/ {for(i=1;i<=NF;i++) if($i ~ /^avg10=/){split($i,a,"="); print int(a[2]+0); exit}}' /proc/pressure/io 2>/dev/null || echo 0)
                    pgmaj=$(awk '$1=="pgmajfault"{print $2; exit}' /proc/vmstat 2>/dev/null || echo 0)
                    allocstall=$(awk '$1 ~ /^allocstall/ {s+=$2} END{print s+0}' /proc/vmstat 2>/dev/null || echo 0)

                    prev_retrans=$(cat "$STATE_DIR/prev_retrans" 2>/dev/null || echo "$retrans")
                    prev_passive=$(cat "$STATE_DIR/prev_passive" 2>/dev/null || echo "$passive")
                    prev_qdisc_drop=$(cat "$STATE_DIR/prev_qdisc_drop" 2>/dev/null || echo "$qdisc_drop")
                    prev_softnet_drop=$(cat "$STATE_DIR/prev_softnet_drop" 2>/dev/null || echo "$softnet_drop")
                    prev_tx_bytes=$(cat "$STATE_DIR/prev_tx_bytes" 2>/dev/null || echo "$tx_bytes")
                    prev_pgmaj=$(cat "$STATE_DIR/prev_pgmaj" 2>/dev/null || echo "$pgmaj")
                    prev_allocstall=$(cat "$STATE_DIR/prev_allocstall" 2>/dev/null || echo "$allocstall")

                    d_retrans=$(( retrans - prev_retrans ))
                    d_passive=$(( passive - prev_passive ))
                    d_drop=$(( (qdisc_drop - prev_qdisc_drop) + (softnet_drop - prev_softnet_drop) ))
                    d_tx=$(( tx_bytes - prev_tx_bytes ))
                    d_pgmaj=$(( pgmaj - prev_pgmaj ))
                    d_allocstall=$(( allocstall - prev_allocstall ))
                    [ "$d_retrans" -lt 0 ] && d_retrans=0
                    [ "$d_passive" -lt 0 ] && d_passive=0
                    [ "$d_drop" -lt 0 ] && d_drop=0
                    [ "$d_tx" -lt 0 ] && d_tx=0
                    [ "$d_pgmaj" -lt 0 ] && d_pgmaj=0
                    [ "$d_allocstall" -lt 0 ] && d_allocstall=0

                    retrans_rate=$(( d_retrans / elapsed ))
                    conn_rate=$(( d_passive / elapsed ))
                    drop_rate=$(( d_drop / elapsed ))
                    tx_mbps=$(( d_tx * 8 / elapsed / 1000000 ))
                    conn_pct=$(( conn_count * 100 / conn_max ))
                    pgmaj_rate=$(( d_pgmaj / elapsed ))
                    allocstall_rate=$(( d_allocstall / elapsed ))

                    probe_tick=$(cat "$STATE_DIR/probe_tick" 2>/dev/null || echo 0)
                    probe_tick=$(( probe_tick + 1 ))
                    if [ "$probe_tick" -ge "$ACTIVE_EVERY" ]; then
                      probe_tick=0
                      probe_out=$(ping -c 4 -i 0.2 -s 32 -W 1 "$TARGET" 2>/dev/null || true)
                      loss_pct=$(echo "$probe_out" | awk -F', ' '/packet loss/ {gsub("%","",$3); print $3+0; exit}')
                      read -r rtt_avg rtt_mdev <<<"$(echo "$probe_out" | awk -F'=' '/^rtt/ {gsub(" ms","",$2); split($2,a,"/"); print a[2]+0, a[4]+0; exit}')"
                      : ''${loss_pct:=0}
                      : ''${rtt_avg:=0}
                      : ''${rtt_mdev:=0}
                      echo "$loss_pct" > "$STATE_DIR/probe_loss"
                      echo "$rtt_avg" > "$STATE_DIR/probe_rtt"
                      echo "$rtt_mdev" > "$STATE_DIR/probe_jitter"
                    else
                      loss_pct=$(cat "$STATE_DIR/probe_loss" 2>/dev/null || echo 0)
                      rtt_avg=$(cat "$STATE_DIR/probe_rtt" 2>/dev/null || echo 0)
                      rtt_mdev=$(cat "$STATE_DIR/probe_jitter" 2>/dev/null || echo 0)
                    fi

                    state=$(cat "$STATE_DIR/state" 2>/dev/null || echo "GREEN")
                    bad=$(cat "$STATE_DIR/bad" 2>/dev/null || echo 0)
                    good=$(cat "$STATE_DIR/good" 2>/dev/null || echo 0)
                    last_change=$(cat "$STATE_DIR/last_change" 2>/dev/null || echo 0)
                    min_dwell=6
                    if [ "$state" = "RED" ]; then
                      min_dwell=10
                    fi

                    # 反惩罚阈值：只在明显进入惩罚区时才收敛，平时保持激进。
                    moderate_retrans=9000
                    severe_retrans=18000
                    moderate_drop=360
                    severe_drop=720
                    moderate_jitter=170
                    severe_jitter=320
                    moderate_loss=30
                    severe_loss=50

                    qos_moderate=0
                    qos_severe=0
                    if [ "$tx_mbps" -gt $(( ${toString cfg.bandwidth} * 75 / 100 )) ] &&
                       { [ "$retrans_rate" -ge "$moderate_retrans" ] || [ "''${loss_pct%.*}" -ge "$moderate_loss" ] || [ "''${rtt_mdev%.*}" -ge "$moderate_jitter" ]; }; then
                      qos_moderate=1
                    fi
                    if [ "$tx_mbps" -gt $(( ${toString cfg.bandwidth} * 90 / 100 )) ] &&
                       { [ "$retrans_rate" -ge "$severe_retrans" ] || [ "''${loss_pct%.*}" -ge "$severe_loss" ] || [ "''${rtt_mdev%.*}" -ge "$severe_jitter" ]; }; then
                      qos_severe=1
                    fi

                    severity=0
                    if [ "$conn_pct" -ge 99 ] || [ "$drop_rate" -ge "$severe_drop" ] || [ "$retrans_rate" -ge "$severe_retrans" ] || [ "$qos_severe" -eq 1 ]; then
                      severity=2
                    elif [ "$conn_pct" -ge 97 ] || [ "$drop_rate" -ge "$moderate_drop" ] || [ "$retrans_rate" -ge "$moderate_retrans" ] || [ "$qos_moderate" -eq 1 ]; then
                      severity=1
                    fi

                    # 内存/IO 抖动保护：避免“暴力发包把本机打抖”导致吞吐塌陷或进程断连。
                    if [ "$mem_psi" -ge 8 ] || [ "$io_psi" -ge 5 ] || [ "$allocstall_rate" -ge 80 ] || [ "$pgmaj_rate" -ge 1200 ]; then
                      severity=2
                    elif [ "$mem_psi" -ge 3 ] || [ "$io_psi" -ge 2 ] || [ "$allocstall_rate" -ge 20 ] || [ "$pgmaj_rate" -ge 300 ]; then
                      if [ "$severity" -lt 1 ]; then
                        severity=1
                      fi
                    fi

                    case "$severity" in
                      2) bad=$(( bad + 2 )); good=0 ;;
                      1) bad=$(( bad + 1 )); good=$(( good > 0 ? good - 1 : 0 )) ;;
                      0) good=$(( good + 1 )); bad=$(( bad > 0 ? bad - 1 : 0 )) ;;
                    esac

                    apply_state() {
                      local next="$1"
                      local cca ss ca icwnd irwnd fqrate global_rate global_burst per_ip_rate per_ip_burst lout bp ndb ndu
                      case "$next" in
                        GREEN)
                          cca="${cfg.cca}"
                          ss=$(( ${toString pacingSsRatio} + 20 ))
                          ca=$(( ${toString pacingCaRatio} + 20 ))
                          icwnd=$(( ${toString initcwnd} + 64 ))
                          irwnd=$(( ${toString initrwnd} + 256 ))
                          fqrate=$(( ${toString cfg.fqMaxrate} * 125 / 100 ))
                          lout=$(( ${toString tcpLimitOutputBytes} * 110 / 100 ))
                          bp=$(( ${toString busy_poll} * 100 / 100 ))
                          ndb=$(( ${toString napi_budget} * 100 / 100 ))
                          ndu=$(( ${toString netdev_budget_usecs} * 100 / 100 ))
                          ;;
                        YELLOW)
                          cca="${cfg.cca}"
                          ss=$(( ${toString pacingSsRatio} * 100 / 100 ))
                          ca=$(( ${toString pacingCaRatio} * 100 / 100 ))
                          icwnd=$(( ${toString initcwnd} * 100 / 100 ))
                          irwnd=$(( ${toString initrwnd} * 100 / 100 ))
                          fqrate=$(( ${toString cfg.fqMaxrate} * 112 / 100 ))
                          lout=$(( ${toString tcpLimitOutputBytes} * 80 / 100 ))
                          bp=$(( ${toString busy_poll} * 70 / 100 ))
                          ndb=$(( ${toString napi_budget} * 85 / 100 ))
                          ndu=$(( ${toString netdev_budget_usecs} * 80 / 100 ))
                          global_rate=40000
                          global_burst=48000
                          per_ip_rate=2800
                          per_ip_burst=3600
                          ;;
                        RED)
                          cca="${cfg.cca}"
                          ss=$(( ${toString pacingSsRatio} * 99 / 100 ))
                          ca=$(( ${toString pacingCaRatio} * 99 / 100 ))
                          icwnd=$(( ${toString initcwnd} * 99 / 100 ))
                          irwnd=$(( ${toString initrwnd} * 99 / 100 ))
                          fqrate=$(( ${toString cfg.fqMaxrate} * 102 / 100 ))
                          lout=$(( ${toString tcpLimitOutputBytes} * 60 / 100 ))
                          bp=$(( ${toString busy_poll} * 40 / 100 ))
                          ndb=$(( ${toString napi_budget} * 70 / 100 ))
                          ndu=$(( ${toString netdev_budget_usecs} * 65 / 100 ))
                          global_rate=26000
                          global_burst=32000
                          per_ip_rate=1700
                          per_ip_burst=2200
                          ;;
                      esac

                      [ "$fqrate" -lt 100 ] && fqrate=100
                      [ "$icwnd" -lt 32 ] && icwnd=32
                      [ "$irwnd" -lt 150 ] && irwnd=150
                      [ "$lout" -lt 524288 ] && lout=524288
                      [ "$bp" -lt 0 ] && bp=0
                      [ "$ndb" -lt 1000 ] && ndb=1000
                      [ "$ndu" -lt 8000 ] && ndu=8000
                      # 防止内核拒绝非法 pacing 比例（例如 >1000）
                      [ "$ss" -gt ${toString pacingSsKernelMax} ] && ss=${toString pacingSsKernelMax}
                      [ "$ss" -lt ${toString pacingSsKernelMin} ] && ss=${toString pacingSsKernelMin}

                      sysctl -w \
                        net.ipv4.tcp_congestion_control="$cca" \
                        net.ipv4.tcp_pacing_ss_ratio="$ss" \
                        net.ipv4.tcp_pacing_ca_ratio="$ca" \
                        net.ipv4.tcp_limit_output_bytes="$lout" \
                        net.core.busy_poll="$bp" \
                        net.core.busy_read="$bp" \
                        net.core.netdev_budget="$ndb" \
                        net.core.netdev_budget_usecs="$ndu" >/dev/null || true

                      DEF4=$(ip -4 route show default dev "$IFACE" | head -n 1)
                      if [ -n "$DEF4" ]; then
                        CUR_MSS=$(echo "$DEF4" | awk '{for(i=1;i<NF;i++) if($i=="advmss"){print $(i+1); exit}}')
                        [ -z "$CUR_MSS" ] && CUR_MSS=1460
                        ip route change $DEF4 initcwnd "$icwnd" initrwnd "$irwnd" advmss "$CUR_MSS" || true
                      fi

                      DEF6=$(ip -6 route show default dev "$IFACE" | head -n 1)
                      if [ -n "$DEF6" ]; then
                        CUR_MSS6=$(echo "$DEF6" | awk '{for(i=1;i<NF;i++) if($i=="advmss"){print $(i+1); exit}}')
                        [ -z "$CUR_MSS6" ] && CUR_MSS6=1440
                        ip -6 route change $DEF6 initcwnd "$icwnd" initrwnd "$irwnd" advmss "$CUR_MSS6" || true
                      fi

                    if [ "${toString cfg.fqMaxrate}" -gt 0 ]; then
                      tc qdisc replace dev "$IFACE" root fq maxrate ''${fqrate}mbit flow_limit 200 quantum 12000 initial_quantum 65536
                    fi

                    if [ "$next" = "GREEN" ] || [ "$next" = "YELLOW" ]; then
                      nft delete table inet qos_guard 2>/dev/null || true
                    else
                        nft -f - <<EOF
          table inet qos_guard
          delete table inet qos_guard
          table inet qos_guard {
            chain input {
              type filter hook input priority filter; policy accept;
              tcp dport { 8443, 8444, 8555 } ct state new limit rate over $global_rate/second burst $global_burst packets drop
              tcp dport { 8443, 8444, 8555 } ct state new meter per_ip4 { ip saddr limit rate over $per_ip_rate/second burst $per_ip_burst packets } drop
              tcp dport { 8443, 8444, 8555 } ct state new meter per_ip6 { ip6 saddr limit rate over $per_ip_rate/second burst $per_ip_burst packets } drop
            }
          }
          EOF
                      fi
                    }

                    next_state="$state"
                    if [ $(( now - last_change )) -ge "$min_dwell" ]; then
                      if [ "$state" = "GREEN" ] && [ "$bad" -ge 12 ]; then
                        next_state="YELLOW"
                      elif [ "$state" = "YELLOW" ] && [ "$bad" -ge 24 ]; then
                        next_state="RED"
                      elif [ "$state" = "RED" ] && [ "$good" -ge 1 ] && [ "$bad" -le 5 ]; then
                        next_state="YELLOW"
                      elif [ "$state" = "YELLOW" ] && [ "$good" -ge 2 ] && [ "$bad" -eq 0 ]; then
                        next_state="GREEN"
                      fi
                    fi

                    if [ "$next_state" != "$state" ]; then
                      apply_state "$next_state"
                      state="$next_state"
                      last_change=$now
                      bad=0
                      good=0
                    else
                      apply_state "$state"
                    fi

                    echo "$now" > "$STATE_DIR/prev_now"
                    echo "$probe_tick" > "$STATE_DIR/probe_tick"
                    echo "$retrans" > "$STATE_DIR/prev_retrans"
                    echo "$passive" > "$STATE_DIR/prev_passive"
                    echo "$qdisc_drop" > "$STATE_DIR/prev_qdisc_drop"
                    echo "$softnet_drop" > "$STATE_DIR/prev_softnet_drop"
                    echo "$tx_bytes" > "$STATE_DIR/prev_tx_bytes"
                    echo "$pgmaj" > "$STATE_DIR/prev_pgmaj"
                    echo "$allocstall" > "$STATE_DIR/prev_allocstall"
                    echo "$state" > "$STATE_DIR/state"
                    echo "$bad" > "$STATE_DIR/bad"
                    echo "$good" > "$STATE_DIR/good"
                    echo "$last_change" > "$STATE_DIR/last_change"
        '';
      };

      systemd.timers.network-qos-controller = lib.mkIf cfg.qosProbe.enable {
        description = "Timer for QoS closed-loop controller";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "45s";
          OnUnitActiveSec = "${toString cfg.qosProbe.intervalSec}s";
          AccuracySec = "1s";
        };
      };

      # ── 服务五：清零出口 DSCP 标记（规避运营商 QoS 分级限速）────────
      # 原理：运营商 DPI 读取 IP 头中的 DSCP/TOS 字段对流量分级限速；
      #        主动将所有出口包 DSCP 清零（CS0 = Best-Effort），
      #        让限速策略无法按 QoS 标记定向命中本机流量。
      systemd.services.clear-dscp = {
        description = "Clear DSCP/TOS on all egress packets to evade ISP QoS classification";
        after = [
          "network-online.target"
          "nftables.service"
        ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        restartTriggers = [
          (builtins.hashString "sha256" config.systemd.services.clear-dscp.script)
        ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = with pkgs; [ nftables ];
        script = ''
          # 用独立表管理 DSCP 清零，与其他 nftables 规则完全隔离
          nft -f - <<'NFTEOF'
          table ip clear_dscp
          delete table ip clear_dscp
          table ip clear_dscp {
            chain postrouting {
              type filter hook postrouting priority mangle; policy accept;
              ip dscp != cs0 ip dscp set cs0
            }
          }
          table ip6 clear_dscp6
          delete table ip6 clear_dscp6
          table ip6 clear_dscp6 {
            chain postrouting {
              type filter hook postrouting priority mangle; policy accept;
              ip6 dscp != cs0 ip6 dscp set cs0
            }
          }
          NFTEOF
          echo "[clear-dscp] DSCP CS0 applied on all egress (IPv4 + IPv6)."
        '';
      };

      # 10. 内核与网络调优
      # 使用 XanMod 核心以获得最新的 BBR 优化 (包括 v3) 和更好的网络吞吐
      # boot.kernelPackages = pkgs.linuxPackages_xanmod_latest;
    })
  ];
}
