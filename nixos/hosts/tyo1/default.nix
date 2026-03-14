{ nixosModules, lib, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.optimize.minimal
      nixosModules.optimize.fakehttp
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
  environment.networkTune = {
    enable = true;
    bandwidth = 1000; # Mbps 单向
    # 单核弱机避免把“理论峰值”直接喂给推导器，否则会放大软中断与队列抖动。
    realBandwidth = 850;
    rtt = 180; # ms，国际线路
    ram = 500; # MB，可用内存
    cpus = 1; # vCPU 数
    highLoss = true; # 高丢包国际线路
    # 主动整形到千兆口的 95%，减少尾丢包与重传风暴。
    fqMaxrate = 950;
  };

  # tyo1 单核 CPU 护栏：保留激进发包能力，同时抑制 ksoftirqd 常驻高占用。
  boot.kernel.sysctl = {
    # 缩短单次 NAPI 批处理窗口，降低单周期占满 CPU 的概率。
    "net.core.netdev_budget" = lib.mkOverride 60 4096;
    "net.core.netdev_budget_usecs" = lib.mkOverride 60 22000;
    "net.core.dev_weight" = lib.mkOverride 60 512;

    # busy-poll 在单核上过高会放大抢占，适度下调。
    "net.core.busy_poll" = lib.mkOverride 60 25;
    "net.core.busy_read" = lib.mkOverride 60 25;

    # 缩小 RPS flow table 与单连接发送积压，减少缓存命中与突发开销。
    "net.core.rps_sock_flow_entries" = lib.mkOverride 60 262144;
    "net.ipv4.tcp_limit_output_bytes" = lib.mkOverride 60 786432;
  };
}
