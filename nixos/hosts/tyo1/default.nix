{ nixosModules, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.optimize.minimal
      ../../modules/optimize/disk-reliability.nix
      # nixosModules.optimize.fakehttp
      # nixosModules.services.traefik
      # nixosModules.services.derp
      (import nixosModules.services.xray {
        # needProxy = true;
        # proxyHosts = [ "nue0.dora.im" "tyo0.dora.im" ];
      })
    ];

  boot.kernelParams = [
    "console=ttyS0"
    "console=tty0"
  ];

  environment.networkOmnitt = {
    realbandwith = 500;
    latencyMs = 180; # ms，国际线路
    memoryMB = 500; # MB，可用内存
  };

  # tyo1 单核 CPU 护栏：保留激进发包能力，同时抑制 ksoftirqd 常驻高占用。
  # boot.kernel.sysctl = {
  #   # 缩短单次 NAPI 批处理窗口，降低单周期占满 CPU 的概率。
  #   "net.core.netdev_budget" = lib.mkOverride 60 4096;
  #   "net.core.netdev_budget_usecs" = lib.mkOverride 60 22000;
  #   "net.core.dev_weight" = lib.mkOverride 60 512;
  #
  #   # busy-poll 在单核上过高会放大抢占，适度下调。
  #   "net.core.busy_poll" = lib.mkOverride 60 25;
  #   "net.core.busy_read" = lib.mkOverride 60 25;
  #
  #   # 缩小 RPS flow table 与单连接发送积压，减少缓存命中与突发开销。
  #   "net.core.rps_sock_flow_entries" = lib.mkOverride 60 262144;
  #   "net.ipv4.tcp_limit_output_bytes" = lib.mkOverride 60 786432;
  # };
}
