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
      nixosModules.optimize.infini
      nixosModules.optimize.ext4
      # nixosModules.optimize.fakehttp
      # nixosModules.services.traefik
      # nixosModules.services.derp
      (import nixosModules.services.xray {
        # needProxy = true;
        # proxyHosts = [ "nue0.dora.im" "tyo0.dora.im" ];
      })
    ];

  boot.kernelParams = [
    "console=ttyS0"
    "console=tty0"
  ];
  environment.networkTune = {
    enable = true;
    bandwidth = 500; # Mbps 单向
    realBandwidth = 500;
    rtt = 200; # ms
    ram = 250; # MB，预留内存给Xray
    cpus = 1; # vCPU 数
    highLoss = true;
    # 禁用 FQ 速率整形墙，配合 BBRv1 的野蛮发包，不受任何人工带宽限制
    fqMaxrate = 0;

    # 强制使用内核原生的 bbr (即 BBRv1，因为我们在 LTS 内核上)，
    # 绕开可能加载失败的 out-of-tree 模块
    cca = "bbr";
  };

  # tyo1 单核 CPU 护栏：强制让渡 CPU 给用户态的 Xray 加解密
  boot.kernel.sysctl = {
    # 适当放开 NAPI 批处理窗口，CPU目前依然充裕（空闲>90%）
    "net.core.netdev_budget" = lib.mkOverride 60 300;
    "net.core.netdev_budget_usecs" = lib.mkOverride 60 12000;
    "net.core.dev_weight" = lib.mkOverride 60 128;

    # 禁用 busy-poll，释放 CPU 回归 Xray 调度
    "net.core.busy_poll" = lib.mkOverride 60 0;
    "net.core.busy_read" = lib.mkOverride 60 0;

    # 放大单连接发送积压。限制太死会导致单流最高测速上不去。
    "net.core.rps_sock_flow_entries" = lib.mkOverride 60 32768;
    "net.ipv4.tcp_limit_output_bytes" = lib.mkOverride 60 1048576;
  };
}
