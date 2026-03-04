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
      nixosModules.services.fakehttp
    ];

  services.kernel-relay = {
    enable = true;
    dnsInterval = "3min";
    enableFlowtable = true;
    ipFamily = "ipv4";
    mappings = [
      {
        listenPort = 50561;
        remoteAddr = "nue0.dora.im";
        remotePort = 8555;
      }
      {
        listenPort = 50562;
        remoteAddr = "hkg4.dora.im";
        remotePort = 8555;
      }
      {
        listenPort = 50563;
        remoteAddr = "tyo0.dora.im";
        remotePort = 8555;
      }
      {
        listenPort = 50564;
        remoteAddr = "hkg5.dora.im";
        remotePort = 8555;
      }
      {
        listenPort = 50565;
        remoteAddr = "82.40.41.218";
        remotePort = 8555;
      }
      {
        listenPort = 50566;
        remoteAddr = "2a13:edc0:24:1d5::a";
        remotePort = 8555;
        ipFamily = "ipv6";
      }
    ];
  };

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
  # networking.firewall.allowedTCPPorts = lib.range 50560 50569;
  # networking.firewall.allowedUDPPorts = lib.range 50560 50569;

  environment.networkTune = {
    enable = true;
    bandwidth = 1000; # Mbps 单向
    realBandwidth = 600; # 持续可用带宽
    rtt = 150; # ms，国际线路
    ram = 2048; # MB，可用内存
    cpus = 1; # vCPU 数
    highLoss = true; # 高丢包国际线路
    # fqMaxrate = realBandwidth × 95% = 570，主动整形防令牌桶尾丢包
    # （已是默认公式，此处显式写出便于各主机理解和覆盖）
    fqMaxrate = 570;
  };
  services.tailscale.enable = lib.mkForce true;
  systemd.services.tailscale-setup.enable = lib.mkForce true;

  services.fakehttp = {
    enable = true;
    # 使用由 Wireshark/tcpdump 提取的二进制 payload (Host: speedtest.jsinfo.net)
    # 比 httpHost 更难被 DPI 发现，模拟真实测速站点的第一个 TLS/HTTP 包
    payloadFile = ../../modules/services/fakehttp_payloads/http_jsinfo_net.bin;
    # cu 作为客户端主动发起的出站 TCP 流量会被混淆（如 iperf3 -c 从 cu 发起）
    # 注：若要解除用户到 cu 的反向上传限速，需在用户侧路由器运行 FakeHTTP
  };
}
