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
      nixosModules.services.traefik
      nixosModules.services.derp
      # nixosModules.services.stun
      (import nixosModules.services.xray {
        # needProxy = true;
      })
      # nixosModules.services.tuic
      # nixosModules.services.perplexica
      nixosModules.services.rustdesk
      # nixosModules.media.jellyfin
      # nixosModules.services.headscale
      # (import nixosModules.services.alist { })
    ];

  environment.networkTune = {
    enable = true;
    bandwidth = 600; # Mbps 单向
    realBandwidth = 500;
    rtt = 200; # ms，国际线路
    ram = 2048; # MB，可用内存
    cpus = 2; # vCPU 数
    highLoss = true; # 高丢包国际线路
  };
}
