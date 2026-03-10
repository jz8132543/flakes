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
      nixosModules.services.traefik
      nixosModules.services.derp
      nixosModules.services.kernel-relay
      nixosModules.optimize.fakehttp
    ];

  services.kernel-relay = {
    enable = true;
    dnsInterval = "3min";
    enableFlowtable = true;
    ipFamily = "ipv4";
    mappings = [
      # SSH
      {
        listenPort = 2022;
        remoteAddr = "138.252.162.101";
        remotePort = 16810;
      }
      {
        listenPort = 8555;
        remoteAddr = "138.252.162.101";
        remotePort = 16811;
      }
    ];
  };

  services.openssh.ports = [
    config.ports.ssh
    22
  ];
  # environment.isNAT = true;
  environment.isCN = true;

  ports.derp-stun = lib.mkForce 8445;
  ports.derp = lib.mkForce 8444;
  # ports.turn-stun = lib.mkForce 50568;
  environment.altHTTPS = 8443;

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
  # networking.firewall.allowedTCPPorts = lib.range 50560 50569;
  # networking.firewall.allowedUDPPorts = lib.range 50560 50569;

  environment.networkTune = {
    enable = true;
    bandwidth = 1000; # Mbps 单向
    realBandwidth = 200; # 持续可用带宽
    rtt = 50; # ms，国际线路
    ram = 1024; # MB，可用内存
    cpus = 1; # vCPU 数
    highLoss = false; # 高丢包国际线路
    # fqMaxrate = realBandwidth × 95% = 570，主动整形防令牌桶尾丢包
    # （已是默认公式，此处显式写出便于各主机理解和覆盖）
    # fqMaxrate = 570;
  };
  services.tailscale.enable = lib.mkForce true;
  systemd.services.tailscale-setup.enable = lib.mkForce true;
}
