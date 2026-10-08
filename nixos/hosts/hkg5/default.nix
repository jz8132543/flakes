{ nixosModules, ... }: {
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.optimize.minimal
      nixosModules.optimize.ext4
      nixosModules.optimize.anti-balloon
      nixosModules.services.networking.dn42.mesh
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
  };

  # ── 350MB 超小内存节点：开机内核级物理内存着色（0 运行期内存开销）──
  services.anti-balloon = {
    bootMemtest = true;
  };

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
