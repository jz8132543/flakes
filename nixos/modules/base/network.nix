{lib, ...}: {
  networking = {
    nameservers = lib.mkDefault ["1.1.1.1" "1.0.0.1"];
    domain = "dora.im";
    search = ["dora.im" "ts.dora.im" "users.dora.im"];
    firewall.enable = true;
    dhcpcd.extraConfig = "nohook resolv.conf";
    networkmanager.dns = lib.mkDefault "none";
  };

  boot = {
    kernel = {
      sysctl = {
        "net.core.default_qdisc" = "cake";
        "net.ipv4.tcp_congestion_control" = "bbr";
        "net.core.rmem_max" = 2500000;
        "net.core.wmem_max" = 2500000;

        "net.ipv4.tcp_fastopen" = 3;
        "net.ipv4.tcp_fin_timeout" = 10;
        "net.ipv4.tcp_keepalive_time" = 60;
        "net.ipv4.tcp_keepalive_intvl" = 10;
        "net.ipv4.tcp_keepalive_probes" = 6;
        "net.ipv4.tcp_max_tw_buckets" = 2000000;
        "net.ipv4.tcp_max_syn_backlog" = 8192;
        "net.ipv4.tcp_mtu_probing" = 1;
        "net.ipv4.tcp_slow_start_after_idle" = 0;
        "net.ipv4.tcp_syncookies" = 1;
        "net.ipv4.tcp_tw_reuse" = 1;

        # tailscale
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
      };
    };
  };
}
