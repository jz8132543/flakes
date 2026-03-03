# nixos/modules/optimize/network.nix
#
# 硬件感知网络调优模块 — 在 Nix 求值期（编译期）根据机器硬件参数
# 动态计算所有 sysctl 值，替代之前的静态写死方案。
#
# 使用方式：在各主机配置里 imports 本文件，然后声明：
#
#   environment.networkTune = {
#     enable    = true;
#     bandwidth = 1000;   # Mbps，单向目标带宽
#     rtt       = 130;    # ms，国际线路预期 RTT
#     ram       = 400;    # MB，可用物理内存（扣除 OS 开销后）
#     cpus      = 1;      # vCPU 核心数
#     highLoss  = true;   # 是否针对高丢包国际线路优化
#   };
#
# ── 关于 CPU 参数的设计说明 ────────────────────────────────────────────
#
# 仅用 cpus（核心数）就能捕获网络调优所需的全部 CPU-related 信息：
#
#   cpus = 1  → 唯一核心承担 app + 网络 + 中断，busy_poll 是负优化；
#               NAPI budget 适中防止中断侧占满 CPU；tcp_retries 短以快速释放资源。
#   cpus >= 2 → 可启用更大批次 NAPI，允许网络中断与应用并发。
#   cpus >= 8 → 高吞吐服务器，超大批次 NAPI，连接队列放大。
#
# 对"CPU 性能强弱"无需单独建模：决定性能的核心因素是 bandwidth（决定缓冲区大小）
# 和 ram（决定内存池分配策略），CPU 主要影响中断策略而非缓冲区大小。
# 若机器使用可突发 VPS CPU（burst credit），无需特殊处理——调参本身不会改变
# 物理 CPU 算力，只优化内核处理路径。
#
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
  # BDP(bytes) = bandwidth(Mbps) * 1e6/8 * rtt(ms)/1000
  #            = bandwidth * rtt * 125
  # 示例：1000Mbps @ 130ms → 16,250,000 B ≈ 15.5 MB
  # 示例：2500Mbps @ 150ms → 46,875,000 B ≈ 44.7 MB
  bdp = cfg.bandwidth * cfg.rtt * 125;

  # ── Socket 缓冲区上限 (rmem_max / wmem_max) ─────────────────────────
  # 需要 ≥ BDP 才能在一个 RTT 内填满管道；
  # 2×BDP 兼容对端为 CUBIC（CUBIC 需 2×BDP 缓冲才不被接收窗口限速）；
  # 上限：12.5% RAM（ram_MB * 1024*1024 / 8 = ram_MB * 131072）；
  # 绝对上限：128 MB（防大内存机器给单 socket 分配过多）。
  rmem_max_raw = bdp * 2;
  rmem_max_pct = cfg.ram * 131072; # 12.5% of RAM in bytes
  rmem_max_limit = 128 * 1024 * 1024; # 128 MB absolute ceiling
  rmem_max = clamp (16 * 1024 * 1024) rmem_max_limit (
    if rmem_max_raw < rmem_max_pct then rmem_max_raw else rmem_max_pct
  );

  # ── 默认缓冲区 (rmem_default / wmem_default) ─────────────────────────
  # !! 这是"起速快"的最关键参数 !!
  #
  # TCP 接收窗口（rwnd）受 socket 缓冲约束：rwnd ≤ socket_buf_size。
  # 若 rmem_default 过小（如 256KB），则握手后 rwnd=256KB，
  # 发送方被限速到 256KB / RTT：
  #   例：256KB / 0.130s = 15.7 Mbps —— 即使 initcwnd=100 也无法突破！
  #
  # 正确做法：rmem_default ≥ BDP/2，让接收窗口从第 1~2 个 RTT 就能
  # 撑住线速传输，内核 tcp_moderate_rcvbuf 会对空闲连接自动缩小缓冲。
  #
  # 下限 4MB，上限 rmem_max/2（避免默认值超过上限，留余量给内核扩展）。
  rmem_default_raw = bdp / 2;
  rmem_default = clamp (4 * 1024 * 1024) (rmem_max / 2) rmem_default_raw;

  # ── 待发送队列上限 (tcp_notsent_lowat) ──────────────────────────────
  # 防止单连接在发送队列里积压过多数据，饿死其他连接。
  # 取 BDP/16，下限 64KB，上限 512KB。
  notsent_lowat = clamp 65536 524288 (bdp / 16);

  # ── TCP/UDP 全局内存池（单位：页，1 页 = 4096 B）──────────────────
  # pages_per_mb = 256
  # LOW  ≈ 15% RAM → 内核不限速阈值
  # MID  ≈ 30% RAM → 开始内存压力回收
  # HIGH ≈ 50% RAM → 硬上限（超出内核丢弃新数据）
  # 额外上限：为 rmem_max 大小连接数 × 64 对应的页数，
  # 防止大内存机器对小带宽场景分配不合比例的池。
  tcp_mem_low = cfg.ram * 256 * 15 / 100; # = ram * 38
  tcp_mem_mid = cfg.ram * 256 * 30 / 100; # = ram * 77
  tcp_mem_high_raw = cfg.ram * 256 * 50 / 100; # = ram * 128
  tcp_mem_high_bw = rmem_max * 64 / 4096; # 64× max-conn cap in pages
  tcp_mem_high = if tcp_mem_high_raw < tcp_mem_high_bw then tcp_mem_high_raw else tcp_mem_high_bw;
  udp_mem_low = tcp_mem_low / 2;
  udp_mem_mid = tcp_mem_mid / 2;
  udp_mem_high = tcp_mem_high / 2;

  # ── 连接队列 ────────────────────────────────────────────────────────
  # netdev_max_backlog 按带宽分档（单位 pps 需求随 Mbps 线性增加）
  netdev_backlog =
    if cfg.bandwidth >= 5000 then
      500000
    else if cfg.bandwidth >= 2000 then
      300000
    else if cfg.bandwidth >= 1000 then
      100000
    else
      50000;

  # SYN 半连接队列按 RAM 分档
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

  # TIME_WAIT 桶：高频短连接代理场景防连接表耗尽
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

  # 孤儿连接上限（每条 ≈ 4 KB 内核内存）
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

  pipe_max =
    if cfg.ram >= 4096 then
      8388608 # 8 MB
    else
      4194304; # 4 MB

  # ── CPU 专项：NAPI 批处理 ────────────────────────────────────────────
  # 单核：适中批次（该核还要跑应用），禁止 busy_poll（空转浪费）
  # 多核：更大批次减少上下文切换，dev_weight 翻倍
  napi_budget =
    if cfg.cpus == 1 then
      600
    else if cfg.cpus <= 4 then
      800
    else
      1000;

  dev_weight = if cfg.cpus == 1 then 64 else 128;

  # busy_poll：吞吐型代理场景永远禁用（非 DPDK 实时金融场景）
  busy_poll = 0;

  # ── nf_conntrack ────────────────────────────────────────────────────
  # 预算：5% RAM，每条目 ≈ 300 B，下限 65536，上限 2M
  conntrack_raw = cfg.ram * 1048576 * 5 / 100 / 300;
  conntrack_max = clamp 65536 2097152 conntrack_raw;

  # ── 重试次数 ────────────────────────────────────────────────────────
  # 高丢包线路：SYN 重试减少，更快感知断线，加速代理重连
  # 单核：tcp_retries2 更激进，快速释放僵死连接占用的资源
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
  # 大内存机几乎不走 swap，小内存机也尽量留 RAM 给网络缓冲
  vm_swappiness = if cfg.ram >= 8192 then 5 else 10;

in
{
  options.environment.networkTune = {
    enable = lib.mkEnableOption "hardware-aware network sysctl tuning (computed at Nix eval time)";

    bandwidth = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      example = 2500;
      description = ''
        单向目标带宽（Mbps）。用于计算 BDP 和 socket 缓冲区大小。
        设置为 NIC 线速和实际可用带宽中较小的那个值。
      '';
    };

    rtt = lib.mkOption {
      type = lib.types.int;
      default = 130;
      example = 50;
      description = ''
        主要流量路径的预期 RTT（毫秒）。
        国际代理服务器通常取 100–150ms；国内服务器取 5–30ms。
        与 bandwidth 共同决定 BDP（带宽延迟积）。
      '';
    };

    ram = lib.mkOption {
      type = lib.types.int;
      example = 406;
      description = ''
        可用物理内存（MB）。建议减去约 64–100MB 的 OS 固定开销后填入。
        决定 tcp_mem 全局内存池和 nf_conntrack 表的大小上限。
      '';
    };

    cpus = lib.mkOption {
      type = lib.types.int;
      default = 1;
      example = 8;
      description = ''
        CPU 核心/线程数。影响：
          - busy_poll：单核必须禁用（空转等待包）
          - NAPI budget：单核偏小防止中断占满 CPU
          - tcp_retries2：单核更激进以快速释放资源
      '';
    };

    highLoss = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        是否针对高丢包国际链路优化（例如过 GFW 的跨境线路）。
        启用后：减少 SYN/SYNACK 重试次数以加速故障感知，
        提高乱序容忍度（tcp_reordering=300 已在 base/network.nix 中设置）。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # ── sysctl 参数（覆盖 base/network.nix 中相应的静态值）──────────
    boot.kernel.sysctl = {

      # ── Socket 缓冲区 ────────────────────────────────────────────────
      # rmem_max = min(2×BDP, 12.5% RAM, 128MB)
      # 计算值（示例）：1000Mbps@130ms → ~31MB; 2500Mbps@150ms → ~90MB
      "net.core.rmem_max" = lib.mkForce rmem_max;
      "net.core.wmem_max" = lib.mkForce rmem_max;
      # rmem_default = BDP/2（快速起速关键）；下限 4MB，上限 rmem_max/2
      # 示例：1000Mbps@130ms → ~7.8MB（vs 之前错误的 256KB）
      "net.core.rmem_default" = lib.mkForce rmem_default;
      "net.core.wmem_default" = lib.mkForce rmem_default;
      "net.ipv4.tcp_rmem" = lib.mkForce "4096 ${toString rmem_default} ${toString rmem_max}";
      "net.ipv4.tcp_wmem" = lib.mkForce "4096 ${toString rmem_default} ${toString rmem_max}";
      # 单连接待发送队列上限：防大流饿死其他流
      "net.ipv4.tcp_notsent_lowat" = lib.mkForce notsent_lowat;
      "net.ipv4.udp_rmem_min" = lib.mkForce 16384;
      "net.ipv4.udp_wmem_min" = lib.mkForce 16384;

      # ── TCP/UDP 内存池（全局，页为单位）────────────────────────────
      "net.ipv4.tcp_mem" =
        lib.mkForce "${toString tcp_mem_low} ${toString tcp_mem_mid} ${toString tcp_mem_high}";
      "net.ipv4.udp_mem" =
        lib.mkForce "${toString udp_mem_low} ${toString udp_mem_mid} ${toString udp_mem_high}";

      # ── 文件描述符 & 管道 ───────────────────────────────────────────
      "fs.file-max" = lib.mkForce file_max;
      "fs.nr_open" = lib.mkForce 10485760; # 单进程上限，保持激进固定值
      "fs.pipe-max-size" = lib.mkForce pipe_max;

      # ── 连接队列 ────────────────────────────────────────────────────
      "net.core.netdev_max_backlog" = lib.mkForce netdev_backlog;
      "net.ipv4.tcp_max_syn_backlog" = lib.mkForce syn_backlog;
      "net.core.somaxconn" = lib.mkForce 65535; # 内核硬限
      "net.ipv4.tcp_max_tw_buckets" = lib.mkForce tw_buckets;
      "net.ipv4.tcp_max_orphans" = lib.mkForce max_orphans;

      # ── CPU：NAPI 批处理 ────────────────────────────────────────────
      "net.core.netdev_budget" = lib.mkForce napi_budget;
      "net.core.netdev_budget_usecs" = lib.mkForce 8000;
      "net.core.dev_weight" = lib.mkForce dev_weight;
      "net.core.busy_poll" = lib.mkForce busy_poll;
      "net.core.busy_read" = lib.mkForce busy_poll;

      # ── 辅助选项内存 ────────────────────────────────────────────────
      "net.core.optmem_max" = lib.mkForce (if cfg.cpus > 1 then 131072 else 65536);

      # ── nf_conntrack ────────────────────────────────────────────────
      "net.netfilter.nf_conntrack_max" = lib.mkForce conntrack_max;
      "net.netfilter.nf_conntrack_tcp_timeout_established" = lib.mkForce 3600;
      "net.netfilter.nf_conntrack_tcp_timeout_time_wait" = lib.mkForce 10;
      "net.netfilter.nf_conntrack_tcp_timeout_fin_wait" = lib.mkForce 10;
      "net.netfilter.nf_conntrack_tcp_timeout_close_wait" = lib.mkForce 10;
      "net.netfilter.nf_conntrack_tcp_timeout_close" = lib.mkForce 5;

      # ── 重试次数 ────────────────────────────────────────────────────
      "net.ipv4.tcp_syn_retries" = lib.mkForce syn_retries;
      "net.ipv4.tcp_synack_retries" = lib.mkForce synack_retries;
      "net.ipv4.tcp_orphan_retries" = lib.mkForce 2;
      "net.ipv4.tcp_retries2" = lib.mkForce tcp_retries2;

      # ── 内存/Swap ────────────────────────────────────────────────────
      "vm.swappiness" = lib.mkForce vm_swappiness;
    };

    # ── initcwnd / initrwnd：路由层写入（sysctl 无法配置）────────────
    # initcwnd=100 → 握手后立即发送 100×MSS≈143KB，
    # 减少高延迟线路的慢启动阶段，与 rmem_default≥BDP/2 配合实现"第一个 RTT 就跑满"。
    systemd.services.set-initcwnd = {
      description = "Set TCP initcwnd/initrwnd=100 on default routes";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = with pkgs; [
        iproute2
        gawk
      ];
      script = ''
        IFACE=$(ip -o link show up | awk -F': ' '!/lo/ {print $2; exit}')
        [ -z "$IFACE" ] && exit 0
        DEF4=$(ip -4 route show default dev "$IFACE" 2>/dev/null | head -1)
        [ -n "$DEF4" ] && ip route change $DEF4 initcwnd 100 initrwnd 100 || true
        DEF6=$(ip -6 route show default dev "$IFACE" 2>/dev/null | head -1)
        [ -n "$DEF6" ] && ip -6 route change $DEF6 initcwnd 100 initrwnd 100 || true
        echo "[set-initcwnd] initcwnd=100 initrwnd=100 on $IFACE"
      '';
    };
  };
}
