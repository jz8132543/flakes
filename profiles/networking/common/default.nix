{ ... }:

{
  networking = {
    # domain = "dora.im";
    search = ["dora.im"];
    firewall.enable = false;
  };

  # BOOT
  boot = {
    cleanTmpDir = true;
    tmpOnTmpfs = false;
    kernelModules = [ "tcp_bbr" ];
    kernel.sysctl."net.ipv4.tcp_congestion_control" = "bbr";
  };
  zramSwap.enable = true;
  time.timeZone = "Asia/Shanghai";
}
