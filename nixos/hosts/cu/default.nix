{
  nixosModules,
  pkgs,
  lib,
  config,
  ...
}:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.optimize.minimal
      nixosModules.optimize.network
      nixosModules.services.traefik
      nixosModules.services.derp
      nixosModules.services.realm
    ];

  services.openssh.ports = [
    config.ports.ssh
    22
  ];
  # environment.isNAT = true;
  environment.isCN = true;

  ports.derp-stun = lib.mkForce 50568;
  ports.derp = lib.mkForce 50567;
  # ports.turn-stun = lib.mkForce 50568;
  environment.altHTTPS = 50569;

  nix.settings.substituters = lib.mkForce [ "https://mirrors.ustc.edu.cn/nix-channels/store" ];

  environment.systemPackages = with pkgs; [
    kxy-script
    nexttrace # 选项10: 路由追踪
    gawk # OsMutation.sh / nws.sh 用到 gawk
    fio # 磁盘性能测试（yabs 优先用本地 fio，否则自动下载）
    iperf3 # 网络性能测试（yabs 优先用本地 iperf3，否则自动下载）
    virt-what
    xz # 解压 .tar.xz 格式的系统镜像
  ];
  networking.firewall.allowedTCPPorts = lib.range 50560 50569;
  networking.firewall.allowedUDPPorts = lib.range 50560 50569;

  environment.networkTune = {
    enable = true;
    bandwidth = 1000; # Mbps 单向，如 tyo1
    rtt = 150; # ms，国际线路
    ram = 2048; # MB，可用内存
    cpus = 1; # vCPU 数
    highLoss = true; # 高丢包国际线路
  };
}
