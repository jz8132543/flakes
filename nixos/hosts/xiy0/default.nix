{
  nixosModules,
  ...
}:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.optimize.minimal
      nixosModules.optimize.fakehttp
      nixosModules.services.matrix-rtc
      # nixosModules.services.traefik
      # nixosModules.services.derp
      (import nixosModules.services.xray {
      })
    ];

  services.matrix-rtc.enable = true;

  environment.networkTune = {
    enable = true;
    bandwidth = 1000; # Mbps 单向
    realBandwidth = 1000; # 持续可用带宽
    rtt = 50; # ms，国际线路
    ram = 1024; # MB，可用内存
    cpus = 1; # vCPU 数
    highLoss = true; # 高丢包国际线路
    cpuBerserk.enable = false;
    # fqMaxrate = realBandwidth × 95% = 570，主动整形防令牌桶尾丢包
    # （已是默认公式，此处显式写出便于各主机理解和覆盖）
    # fqMaxrate = 570;
  };
}
