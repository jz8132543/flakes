{ nixosModules, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.optimize.infini
      ../../modules/optimize/disk-reliability.nix
      # nixosModules.optimize.fakehttp
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
    bandwidth = 700; # 手动输入
    realBandwidth = 500;
    rtt = 60; # ms，国际线路
    ram = 350; # MB，可用内存
    cpus = 1; # vCPU 数
    highLoss = true; # 高丢包国际线路
  };
}
