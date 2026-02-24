{ nixosModules, pkgs, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      nixosModules.services.telegraf
      nixosModules.services.doraim
      nixosModules.services.derp
      # nixosModules.services.stun
      (import nixosModules.services.xray {
        needProxy = true;
        proxyHost = "nue0.dora.im";
      })
      # nixosModules.services.tuic
      nixosModules.services.searx
      # nixosModules.services.perplexica
      nixosModules.services.rustdesk
      nixosModules.services.murmur
      nixosModules.services.teamspeak
      nixosModules.services.media.nixflix
      nixosModules.services.realm
      # nixosModules.media.jellyfin
      # nixosModules.services.headscale
      # (import nixosModules.services.alist { })
    ];

  environment.systemPackages = with pkgs; [
    # kxy.sh 本体及其依赖（已通过 makeWrapper 注入，此处额外补全系统层面的包）
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
