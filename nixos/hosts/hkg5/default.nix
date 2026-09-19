{ nixosModules, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.optimize.minimal
      nixosModules.optimize.ext4
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
    enableIpv4 = true;
    enableIpv6 = true;
    edgeDomain = "hkg5.dora.im";
    edgePublicIp = "216.23.94.148";
    edgePublicIpv6 = "2401:2660:2:93::a";
    enableCoturn = true;
    centralNatsHost = "nue0.dora.im";
    centralNextcloudUrl = "https://cloud.dora.im";
    enableCluster = true;
    grpcPort = 9090;
    clusterTargets = [
      "sjc0.mag:9090"
      "cu.mag:9090"
    ];
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

  networking.hosts."100.64.0.4" = [
    "cu.dora.im"
    "cuv6.dora.im"
  ];
}
