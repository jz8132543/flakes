{ nixosModules, ... }: {
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.services.networking.dn42.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.optimize.minimal
      nixosModules.optimize.ext4
      nixosModules.optimize.anti-balloon
      # ../../modules/optimize/disk-reliability.nix
      # nixosModules.optimize.fakehttp
      nixosModules.services.traefik
      nixosModules.services.atc.edge
      # nixosModules.services.derp
      (import nixosModules.services.xray {
        needProxy = true;
      })
      nixosModules.nextcloud.talk-edge
    ];

  # ── 分布式 Nextcloud Talk HPB 边缘数据/信令面 ────────────────
  services.nextcloud-talk-edge = {
    enable = true;
    nodeName = "hkg5";
  };

  environment.networkTune = {
    enable = true;
    bandwidth = 100; # 手动输入
    realBandwidth = 100;
    rtt = 100; # ms，国际线路
    ram = 2000; # MB，可用内存
    cpus = 2; # vCPU 数
    highLoss = true; # 高丢包国际线路
  };
}
