{ nixosModules, lib, ... }: {
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.services.networking.dn42.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.optimize.minimal
      nixosModules.optimize.ext4
      nixosModules.optimize.anti-balloon
      nixosModules.optimize.brutal
      # ../../modules/optimize/disk-reliability.nix
      nixosModules.services.traefik
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

  # Use the audited kernel backend without a ~1 GiB userspace dummy pool.
  # This is best effort, not a remedy for host CPU steal or a RAM reservation.
  services.anti-balloon = {
    memoryFiller = false;
    kernel.enable = true;
  };

  # Host CPU steal caused a 5-minute activation timeout after only ~4s of CPU.
  systemd.services.home-manager-tippy.serviceConfig.TimeoutStartSec = lib.mkForce "15min";

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
