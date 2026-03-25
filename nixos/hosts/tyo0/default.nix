{
  nixosModules,
  lib,
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
      # nixosModules.services.traefik
      # nixosModules.services.derp
      (import nixosModules.services.xray {
      })
    ];

  environment.networkTune = {
    enable = true;
    bandwidth = 1000; # Mbps 单向
    realBandwidth = 1000;
    rtt = 200; # ms，国际线路
    ram = 350; # MB，可用内存
    cpus = 1; # vCPU 数
    highLoss = true; # 高丢包国际线路
  };

  # 低 CPU 版本：只保留一小块、使用最快的压缩算法，尽量把 zram 的 CPU 开销压到最低。
  zramSwap = {
    enable = lib.mkOverride 40 true;
    algorithm = "lz4";
    memoryPercent = 12;
    memoryMax = 64 * 1024 * 1024;
    priority = 10;
  };

  # 提前让 userspace OOM 管理器介入，避免等到内核真正 OOM 才处理。
  services.earlyoom = {
    freeMemThreshold = 15;
    freeSwapThreshold = 15;
    freeMemKillThreshold = 7;
    freeSwapKillThreshold = 7;
    reportInterval = 3600;
  };

  # 给 xray 单独设内存压力阈值，让它在接近上限时先被 cgroup 回收/节流。
  systemd.services.xray.serviceConfig = {
    MemoryHigh = "180M";
    ManagedOOMMemoryPressure = "kill";
    ManagedOOMMemoryPressureLimit = "60%";
  };
}
