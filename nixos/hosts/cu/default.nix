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
      nixosModules.services.traefik
      nixosModules.services.small
      nixosModules.services.derp
      nixosModules.services.realm
    ];

  services.openssh.ports = [
    config.ports.ssh
    22
  ];
  environment.isNAT = true;
  environment.isCN = true;

  ports.derp-stun = lib.mkForce 50568;
  ports.derp = lib.mkForce 50567;
  # ports.turn-stun = lib.mkForce 50568;
  environment.altHTTPS = 50569;

  nix.settings.substituters = lib.mkForce [ "https://mirrors.ustc.edu.cn/nix-channels/store" ];

  environment.systemPackages = with pkgs; [
    kxy-script
    nexttrace # 选项10: 路由追踪

    # ---- 子脚本依赖 ----

    # bench.sh / nws.sh: 网速测试，依赖 speedtest-cli 二进制（脚本自动下载）
    # 以下为脚本运行所需的本地工具：
    gawk # OsMutation.sh / nws.sh 用到 gawk

    # yabs.sh: Yet Another Bench Script
    fio # 磁盘性能测试（yabs 优先用本地 fio，否则自动下载）
    iperf3 # 网络性能测试（yabs 优先用本地 iperf3，否则自动下载）

    # OsMutation.sh (LXC/OpenVZ 重装脚本): 需要 virt-what 检测虚拟化类型
    virt-what
    xz # 解压 .tar.xz 格式的系统镜像

    # 其余工具（curl/wget/bc/jq/iproute2/ping 等已在 baseline-apps 中提供）
  ];
}
