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
        # 使用 BBR 拥塞控制（快速起速）
        "net.core.default_qdisc" = "fq";
        "net.ipv4.tcp_congestion_control" = "bbr";

        # 增加缓冲区大小（保证高带宽）
        "net.core.rmem_max" = 134217728;
        "net.core.wmem_max" = 134217728;
        "net.core.netdev_max_backlog" = 300000;

        # TCP 内存优化（三档：最小值/默认值/最大值）
        "net.ipv4.tcp_rmem" = "4096 131072 134217728";
        "net.ipv4.tcp_wmem" = "4096 131072 134217728";

        # 提高文件描述符限制
        "fs.file-max" = 2097152;

        # TIME-WAIT 优化（减少延迟连接残留）
        "net.ipv4.tcp_tw_reuse" = 1;

        # 启用 TCP Fast Open（减少握手延迟）
        "net.ipv4.tcp_fastopen" = 3;

        # 启用 TCP 窗口自动调节
        "net.ipv4.tcp_window_scaling" = 1;

        # 减少 SYN 队列丢包
        "net.ipv4.tcp_max_syn_backlog" = 262144;
        "net.core.somaxconn" = 65535;

        # 开启低延迟队列调度
        "net.ipv4.tcp_low_latency" = 1;

        # 提高 ephemeral port 范围
        "net.ipv4.ip_local_port_range" = "10240 65535";

        # OLD
        # "net.core.default_qdisc" = "fq";
        # "net.ipv4.tcp_congestion_control" = "bbr";
        # "net.core.rmem_max" = 314217728;
        # "net.core.wmem_max" = 314217728;
        # "net.core.somaxconn" = 4096;

        # "net.ipv4.tcp_fastopen" = 3;
        "net.ipv4.tcp_fin_timeout" = 10;
        "net.ipv4.tcp_keepalive_time" = 60;
        "net.ipv4.tcp_keepalive_intvl" = 10;
        "net.ipv4.tcp_keepalive_probes" = 6;
        "net.ipv4.tcp_max_tw_buckets" = 2000000;
        # "net.ipv4.tcp_max_syn_backlog" = 8192;
        "net.ipv4.tcp_mtu_probing" = 1;
        "net.ipv4.tcp_slow_start_after_idle" = 0;
        "net.ipv4.tcp_syncookies" = 1;
        # "net.ipv4.tcp_tw_reuse" = 1;

        # tailscale
        "net.ipv4.ip_forward" = 1;
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
