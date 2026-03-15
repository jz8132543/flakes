{ nixosModules, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.optimize.minimal
      # nixosModules.optimize.fakehttp
      # nixosModules.services.traefik
      # nixosModules.services.derp
      (import nixosModules.services.xray {
        needProxy = true;
      })
    ];

  boot.kernelParams = [
    "console=ttyS0"
    "console=tty0"
  ];
  environment.networkTune = {
    enable = true;
    bandwidth = 500; # Mbps 单向
    realBandwidth = 500;
    rtt = 100; # ms，国际线路
    ram = 500; # MB，可用内存
    cpus = 1; # vCPU 数
    highLoss = false; # 高丢包国际线路
    cpuBerserk.isVirtualMachine = true; # VPS：跳过物理机专属 cpufreq/C-state 调优
  };
}
