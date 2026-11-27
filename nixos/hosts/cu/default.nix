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
    ++ nixosModules.services.networking.dn42.all
    ++ nixosModules.services.ctyun-dashboard.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.optimize.minimal
      nixosModules.optimize.anti-balloon
      nixosModules.optimize.brutal
      # nixosModules.optimize.infini
      # nixosModules.services.derp
      nixosModules.services.haproxy-proxy
      nixosModules.nextcloud.talk-edge
      nixosModules.services.livekit.all
      ../../modules/services/livekit-suite/infrastructure.nix
      nixosModules.services.rustdesk.relay
    ];

  optimize.brutal.target = "!cn";
  services.ctyun-dashboard.enable = true;
  services.livekitSuite = {
    redis.enable = false;
    web.enable = false;
    _meta = {
      domain = "livekit-cu.dora.im";
      httpsPort = config.environment.altHTTPS;
      turnDomain = "livekit-turn-cu.dora.im";
      publicIpv6 = "2408:8207:25b1:2701:6666:16:3efc:9adf";
      privateAddress = "cu.ts";
      region = "cn";
      latitude = 35.0;
      longitude = 105.0;
    };
  };
  services.rustdesk-server.cluster = {
    relayPort = config.ports.rustdesk-relay-cu;
  };

  services.nextcloud-talk-edge = {
    # cu 拥有独立公网 IPv6 地址，仅启用 IPv6 模式（拓扑参数继承自 data.nix）
    enable = true;
    stunServer = "stun.nextcloud.com";
  };

  boot.loader.grub.device = lib.mkForce "nodev";
  boot.loader.grub.devices = lib.mkForce [ "nodev" ];

  # Public TCP/UDP 50560-50569 mapping plan:
  # 50560: SSH management; 50561-50565: kernel-relay forwards to regional
  # services; 50566: RustDesk hbbr (public relay -> local TCP 21117);
  # 50567: EasyTier bootstrap (WS/QUIC); 50568: DN42 NAT-T; 50569: alternate
  # HTTPS. Keep each provider-mapped port assigned to exactly one service.
  services.kernel-relay = {
    enable = true;
    dnsInterval = "3min";
    # enableFlowtable = true;
    ipFamily = "ipv4";
    haproxy.stats = {
      enable = true;
      port = 8404; # 仅在 Tailscale 内网 (http://cu.ts:8404) 可访问，不占用公网端口
    };
    mappings = [
      {
        listenPort = 50561;
        remoteAddr = "fra0.dora.im";
        remotePort = 8555;
      }
      {
        listenPort = 50562;
        remoteAddr = "fra1.dora.im";
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
        remoteAddr = "tyo1.dora.im";
        remotePort = 8555;
      }
    ];
  };

  services.openssh.ports = [
    config.ports.ssh
    22
  ];
  # environment.isNAT = true;
  environment.isCN = true;

  services.easytierMesh = {
    publicHosts = [
      "cu.dora.im"
      "cuv6.dora.im"
      "cm.dora.im"
      "cmv6.dora.im"
    ];
    protocols = {
      ws.port = 50567;
      # wss.bootstrapPort = 50566;
      quic.port = 50567;
      # quic.bootstrapPort = 50566;
    };
  };
  # ports.derp-stun = lib.mkForce 50568;
  # services.traefik.proxies.derp.rule = lib.mkForce "Host(`${config.networking.fqdn}`)";
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
  services.dn42 = {
    ikePort = 500;
    natTPort = 50568; # 利用 cu 1:1 映射至公网的 50568 端口
  };

  # Provider-mapped 50560-50569 TCP/UDP allocation:
  # 50560 SSH management, 50561-50565 regional kernel-relay forwards,
  # 50566 RustDesk hbbr (nft redirects to local 21117), 50567 EasyTier
  # bootstrap, 50568 DN42 NAT-T, and 50569 alternate HTTPS. Keep these
  # assignments unique; RustDesk clients use cu.dora.im:50566 (IPv4 capable).
  networking.firewall.allowedTCPPorts = lib.range 50560 50569;
  networking.firewall.allowedUDPPorts = lib.range 50560 50569;
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
    fqMaxrate = 590;
  };
}
