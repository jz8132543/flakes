{ nixosModules, ... }:
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
    realBandwidth = 1000;
    rtt = 180; # ms，国际线路
    ram = 500; # MB，可用内存
    cpus = 1; # vCPU 数
    highLoss = true; # 高丢包国际线路
  };
}
