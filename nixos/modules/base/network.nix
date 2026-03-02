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
        # Socket 接收/发送缓冲区上限，决定单连接最大可缓存数据量（128 MB 支撑 5 Gbps × 200 ms BDP）
        "net.core.rmem_max" = 134217728;
        "net.core.wmem_max" = 134217728;
        # 网卡收包中断时内核输入队列深度，万兆网卡突发时防丢包
        "net.core.netdev_max_backlog" = 300000;
        # 每个 socket 的辅助选项内存上限（ancillary data / cmsg）
        "net.core.optmem_max" = 65535;
        # TCP 接收/发送缓冲区三档（最小/默认/最大），内核根据实际流量动态调整
        "net.ipv4.tcp_rmem" = "4096 131072 134217728";
        "net.ipv4.tcp_wmem" = "4096 131072 134217728";
        # TCP/UDP 协议栈全局总内存上限（页为单位），超出压力档内核开始回收，防 OOM
        "net.ipv4.tcp_mem" = "786432 1048576 134217728";
        "net.ipv4.udp_mem" = "786432 1048576 134217728";
        # UDP socket 接收/发送最小保证缓冲，内存紧张时防止缓冲被压得过小（WireGuard/QUIC）
        "net.ipv4.udp_rmem_min" = 8192;
        "net.ipv4.udp_wmem_min" = 8192;
        # 允许内核根据实际吞吐自动缩减 TCP 接收缓冲，低速连接节省内存
        "net.ipv4.tcp_moderate_rcvbuf" = 1;
        # 接收窗口缩放因子：值为 2 时应用缓冲占 1/4，内核协议栈占 3/4，通告窗口更激进
        "net.ipv4.tcp_adv_win_scale" = 2;
        # 允许接收窗口超过 64 KB，高带宽高延迟（BDP 大）场景下必须开启
        "net.ipv4.tcp_window_scaling" = 1;

        # ── 文件描述符 ────────────────────────────────────────────────────
        # 内核全局可打开 fd 总数（连接/文件/管道均消耗 fd）
        "fs.file-max" = 2097152;
        # 单进程可打开 fd 上限，是 nofile 硬限制的天花板，须 ≥ file-max
        "fs.nr_open" = 2097152;

        # ── 连接队列容量 ──────────────────────────────────────────────────
        # SYN 半连接队列（三次握手未完成），抗 SYN flood 时能撑住更多新请求
        "net.ipv4.tcp_max_syn_backlog" = 262144;
        # listen() 全连接队列上限，应用层 backlog 不能超过此值
        "net.core.somaxconn" = 65535;
        # TIME-WAIT 连接最大数量，超出后内核强制销毁最老的，防连接表耗尽
        "net.ipv4.tcp_max_tw_buckets" = 2000000;
        # 孤儿连接（fd 已关闭但 TCP 未断）上限，超出强制 RST，防内存泄漏
        "net.ipv4.tcp_max_orphans" = 65535;

        # ── 握手 & 连接复用 ───────────────────────────────────────────────
        # TCP Fast Open：SYN 阶段直接携带数据，省去一个 RTT（3=客户端+服务端同时启用）
        "net.ipv4.tcp_fastopen" = 3;
        # 作为客户端时复用 TIME-WAIT 连接用于新出向连接，减少端口耗尽
        "net.ipv4.tcp_tw_reuse" = 1;
        # RFC1337 保护：忽略 TIME-WAIT 期间收到的 RST，防伪造 RST 提前终止连接
        "net.ipv4.tcp_rfc1337" = 1;
        # SYN Cookie：SYN 队列满时用加密 cookie 代替表项，仍能接受合法连接
        "net.ipv4.tcp_syncookies" = 1;
        # 出向临时端口范围，决定单机并发出向连接上限（~55000 个端口）
        "net.ipv4.ip_local_port_range" = "10240 65535";

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
        # 关闭 ECN：大陆运营商/GFW 中间设备常丢弃 ECN 标记的包，开启反增丢包
        "net.ipv4.tcp_ecn" = 0;
        # 关闭 F-RTO：高丢包时易将真实超时误判为虚假超时，从而压制合理重传
        "net.ipv4.tcp_frto" = 0;
        # 不缓存历史路由指标（RTT/cwnd）：线路质量波动大时旧指标会误导新连接速率
        "net.ipv4.tcp_no_metrics_save" = 1;
        # 路径 MTU 探测：1=检测到黑洞后触发，GFW 屏蔽 ICMP 时自动恢复大包传输
        "net.ipv4.tcp_mtu_probing" = 1;
        # 空闲后不降速重新慢启动，代理/长连接恢复发送时维持原拥塞窗口
        "net.ipv4.tcp_slow_start_after_idle" = 0;

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
