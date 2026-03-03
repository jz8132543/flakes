{ lib, ... }:
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
    # search = ["ts.dora.im" "users.dora.im"];
    dhcpcd.extraConfig = "nohook resolv.conf";
    # networkmanager.dns = lib.mkDefault "none";
  };

  boot = {
    kernel = {
      sysctl = {
        # ── 拥塞控制 & 发包队列 ──────────────────────────────────────────
        # FQ（Fair Queue）：按流独立排队，防止大流占满队列头阻塞小流，BBR 的标准搭档
        "net.core.default_qdisc" = "fq";
        # BBR：基于带宽+RTT 建速率模型，不依赖丢包信号，高延迟/高丢包下远优于 CUBIC
        "net.ipv4.tcp_congestion_control" = "bbr";

        # ── Socket 缓冲区 ─────────────────────────────────────────────────
        # 设计依据（RTT=150ms，目标 2.5 Gbps 单向）：
        #   单连接 BDP = 2500 × 125000 × 0.150 = 46,875,000 B ≈ 44.7 MB
        #   rmem_max = 128 MB ≈ 2.7×BDP，覆盖 CUBIC 对端（需 2×BDP）及多流场景
        #   rmem_default = 8 MB：高速连接快速起步，内核自动扩张到实际所需
        # Socket 接收/发送缓冲区单连接上限（128 MB 支撑 2.5Gbps×150ms BDP 2.7 倍余量）
        "net.core.rmem_max" = 134217728; # 128 MB
        "net.core.wmem_max" = 134217728; # 128 MB
        # 新连接默认缓冲（8 MB：高速线路快速起步，远大于低配机的 256KB）
        "net.core.rmem_default" = 8388608; # 8 MB
        "net.core.wmem_default" = 8388608; # 8 MB
        # TCP 三档缓冲（min / init / max）：init=8MB，高速连接无需冷启动等待
        "net.ipv4.tcp_rmem" = "4096 8388608 134217728";
        "net.ipv4.tcp_wmem" = "4096 8388608 134217728";
        # 限制单连接待发送队列深度，防大流饿死其他流（256KB 足够多Gbps场景）
        "net.ipv4.tcp_notsent_lowat" = 262144; # 256 KB
        # UDP 最小保证（WireGuard/QUIC），不被内存压力压缩
        "net.ipv4.udp_rmem_min" = 16384;
        "net.ipv4.udp_wmem_min" = 16384;
        # 允许内核根据实际吞吐自动缩减 TCP 接收缓冲，低速连接节省内存
        "net.ipv4.tcp_moderate_rcvbuf" = 1;
        # 接收窗口缩放因子：值为 2 时应用缓冲占 1/4，内核协议栈占 3/4，通告窗口更激进
        "net.ipv4.tcp_adv_win_scale" = 2;
        # 允许接收窗口超过 64 KB，高带宽高延迟（BDP 大）场景下必须开启
        "net.ipv4.tcp_window_scaling" = 1;

        # ── TCP/UDP 全局内存池（页 = 4096 B）──────────────────────────────
        # !! 原注释中 134217728 若作为页数 = 512 GB，是错误的（应为字节）
        # 正确做法：以页数为单位，假设机器 ≥ 16GB RAM，分配约 30% 给 TCP
        # LOW = 524288 页 = 2 GB  → 低于此内核不限速
        # MID = 786432 页 = 3 GB  → 开始内存压力回收
        # HIGH = 1048576 页 = 4 GB → 硬上限（≈ 16GB RAM 的 25%）
        # 如果机器 RAM > 32GB，可按比例翻倍（mkForce 在 host 级覆盖即可）
        "net.ipv4.tcp_mem" = "524288 786432 1048576";
        # UDP 池约为 TCP 的一半
        "net.ipv4.udp_mem" = "262144 393216 524288";

        # ── 文件描述符 ────────────────────────────────────────────────────
        "fs.file-max" = 2097152; # 2M fd（大型代理/容器场景）
        "fs.nr_open" = 10485760; # 10M（单进程上限）
        "fs.pipe-max-size" = 8388608; # 8 MB（大管道加速数据中转）

        # ── 连接队列容量 ──────────────────────────────────────────────────
        # NIC 入口环形队列：10Gbps 级 NIC 需要深队列防突发丢包
        "net.core.netdev_max_backlog" = 300000;
        # SYN 半连接队列：大型代理服务器高并发新建
        "net.ipv4.tcp_max_syn_backlog" = 524288;
        # listen() 全连接队列上限（内核硬限）
        "net.core.somaxconn" = 65535;
        # TIME-WAIT 上限：高频短连接场景防连接表耗尽
        "net.ipv4.tcp_max_tw_buckets" = 2000000;
        # 孤儿连接上限（每条约占 4KB 内核内存）
        "net.ipv4.tcp_max_orphans" = 131072;

        # ── 软中断（NAPI）批处理 ──────────────────────────────────────────
        # 多核机器每核软中断处理量，2.5Gbps+ 需要更大批次减少切换开销
        "net.core.netdev_budget" = 1000;
        "net.core.netdev_budget_usecs" = 8000; # 8ms 时间窗（默认 2ms）
        "net.core.dev_weight" = 128;

        # ── 辅助选项内存 ──────────────────────────────────────────────────
        # 多核机器可以给更大的 cmsg/ancdata 缓冲
        "net.core.optmem_max" = 131072; # 128 KB

        # ── nf_conntrack：大机器可以给更大表 ─────────────────────────────
        # 每条约 300B；1048576 × 300B ≈ 300MB（对 ≥32GB 机器可接受）
        # 代理 10000 并发 × 4 方向 = 40000 条目，1048576 有 26× 余量
        "net.netfilter.nf_conntrack_max" = 1048576;
        # established 超时缩短：代理连接不会空闲 5 天
        "net.netfilter.nf_conntrack_tcp_timeout_established" = 3600;
        # 关闭状态超时缩短：加速条目回收
        "net.netfilter.nf_conntrack_tcp_timeout_time_wait" = 15;
        "net.netfilter.nf_conntrack_tcp_timeout_fin_wait" = 15;
        "net.netfilter.nf_conntrack_tcp_timeout_close_wait" = 15;
        "net.netfilter.nf_conntrack_tcp_timeout_close" = 5;

        # ── 握手 & 连接复用 ───────────────────────────────────────────────
        # TCP Fast Open：在我们的代理场景是负优化（SYN 携带数据容易被流量识别），显式禁用
        # "net.ipv4.tcp_fastopen" = 3;   ← 保持注释
        # 作为客户端时复用 TIME-WAIT 连接用于新出向连接，减少端口耗尽
        "net.ipv4.tcp_tw_reuse" = 1;
        # RFC1337 保护：忽略 TIME-WAIT 期间收到的 RST，防伪造 RST 提前终止连接
        "net.ipv4.tcp_rfc1337" = 1;
        # SYN Cookie：SYN 队列满时用加密 cookie 代替表项，仍能接受合法连接
        "net.ipv4.tcp_syncookies" = 1;
        # 出向临时端口范围，决定单机并发出向连接上限
        "net.ipv4.ip_local_port_range" = "1024 65535";

        # ── SYN/孤儿重试次数 ──────────────────────────────────────────────
        # SYN 重试次数：默认 6（约 127s），高延迟高丢包线路 4 次（约 31s）足够
        # 比 minimal 的 3 次略宽松，适合大机器承接更多入向新连接尝试
        "net.ipv4.tcp_syn_retries" = 4;
        # SYNACK 重试次数：默认 5（约 190s），3 次（约 46s）更快释放半连接
        "net.ipv4.tcp_synack_retries" = 3;
        # 孤儿连接重试：默认 0→内核映射为 8，显式设 2 加快孤儿释放（4KB/条内核内存）
        "net.ipv4.tcp_orphan_retries" = 2;

        # ── Busy Polling（吞吐场景明确禁用）─────────────────────────────
        # 代理/转发场景目标是最大吞吐而非极低延迟，busy poll 浪费 CPU 周期
        # 如果此机器同时承担低延迟实时业务（trading 等），可改为 10-50µs
        "net.core.busy_poll" = 0;
        "net.core.busy_read" = 0;

        # ── 内存/Swap 亲和性 ──────────────────────────────────────────────
        # 高性能机器 RAM 充裕，几乎不走 swap；Swap I/O 会增加网络处理抖动
        "vm.swappiness" = 5;

        # ── Keepalive & 超时 ──────────────────────────────────────────────
        # 连接空闲 60s 后开始发 keepalive 探测（默认 7200s），快速发现断线
        "net.ipv4.tcp_keepalive_time" = 60;
        # 两次 keepalive 探测间隔
        "net.ipv4.tcp_keepalive_intvl" = 10;
        # 连续失败 6 次（共 60s）后判定连接断开
        "net.ipv4.tcp_keepalive_probes" = 6;
        # FIN-WAIT-2 超时（默认 60s），主动关闭方等待对端 FIN 的时长
        "net.ipv4.tcp_fin_timeout" = 10;

        # ── 高延迟 / 高丢包线路专项 ──────────────────────────────────────
        # SACK（选择确认）：丢包时只重传缺失的段，高丢包线路带宽利用率大幅提升
        "net.ipv4.tcp_sack" = 1;
        # 时间戳：精确测量 RTT（BBR 重度依赖），同时启用 PAWS 防旧重复包
        "net.ipv4.tcp_timestamps" = 1;
        # 加速 SACK 处理：关闭选择性确认的延迟合并，让网卡接收到失序确认时立即被处理
        "net.ipv4.tcp_comp_sack_delay_ns" = 0;
        # 显式拥塞通知 (ECN)：1 表示全面开启，配合 BBR 可有效降低抖动
        "net.ipv4.tcp_ecn" = 1;
        # ECN 回退：保持开启，兼容不支持 ECN 的链路
        "net.ipv4.tcp_ecn_fallback" = 1;
        # 尾部丢包探测 (TLP)：4 为激进策略，比旧版更加先进，更快地在丢包时补发数据
        "net.ipv4.tcp_early_retrans" = 4;
        # F-RTO：处理超时伪重传，保持 2 (现代内核默认)
        "net.ipv4.tcp_frto" = 2;
        # 乱序重排：在容易乱序的高丢包网络下极大减少误判重传，设置为高乱序容忍 300
        "net.ipv4.tcp_reordering" = 300;
        "net.ipv4.tcp_max_reordering" = 300;
        # 不缓存历史路由指标（RTT/cwnd）：线路质量波动大时旧指标会误导新连接速率
        "net.ipv4.tcp_no_metrics_save" = 1;
        # 路径 MTU 探测：1=检测到黑洞后触发，GFW 屏蔽 ICMP 时自动恢复大包传输
        "net.ipv4.tcp_mtu_probing" = 1;
        # 空闲后不降速重新慢启动，代理/长连接恢复发送时维持原拥塞窗口
        "net.ipv4.tcp_slow_start_after_idle" = 0;
        # 开启 RACK 丢失检测算法
        "net.ipv4.tcp_recovery" = 1;
        # TCP 重传折叠：保持开启
        "net.ipv4.tcp_retrans_collapse" = 1;

        # ── 故障响应 & 多路径 ─────────────────────────────────────────────
        # 缩短僵死连接的存活时间，从 12 降低到 8（约不到 1 分钟即可判定断线），加速代理重连
        "net.ipv4.tcp_retries2" = 8;

        # 多路径 TCP (MPTCP) 支持 (如果内核支持)
        "net.mptcp.enabled" = 1;
        "net.mptcp.checksum_enabled" = 0; # 关闭MPTCP附加校验和以节省 CPU
        "net.netfilter.nf_conntrack_checksum" = 0; # 关闭 netfilter 的校验和验证以节省 CPU
        "net.mptcp.scheduler" = "default";

        # ── 转发（Tailscale / 容器）──────────────────────────────────────
        # 允许内核在不同接口间转发 IPv4 数据包，Tailscale 子网路由必须
        "net.ipv4.ip_forward" = 1;
        # IPv6 转发，同上
        "net.ipv6.conf.all.forwarding" = 1;
      };
    };
  };
  # IPv4 first
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
    precedence ::ffff:0:0/96  100 # increase the precedence of ipv4 addresses
  '';
}
