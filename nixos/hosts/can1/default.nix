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
      # nixosModules.services.traefik
      # nixosModules.services.derp
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
        listenPort = 2022; # 26696
        remoteAddr = "138.252.162.101";
        remotePort = 16810;
      }
      {
        listenPort = 8555; # 51685
        remoteAddr = "138.252.162.101";
        remotePort = 16811;
      }
      {
        listenPort = 16812; # 56071
        remoteAddr = "138.252.162.101";
        remotePort = 16812;
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

  environment.networkOmnitt = {
    latencyMs = 50; # ms，国际线路
  };
  services.tailscale.enable = lib.mkForce true;
  systemd.services.tailscale-setup.enable = lib.mkForce true;
}
