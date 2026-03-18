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
        needProxy = true;
      })
    ];

  boot.kernelParams = [
    "console=ttyS0"
    "console=tty0"
  ];

  environment.networkOmnitt = {
    bandwith = 700; # 手动输入
    realbandwith = 500;
    latencyMs = 60; # ms，国际线路
    memoryMB = 350; # MB，可用内存
  };
}
