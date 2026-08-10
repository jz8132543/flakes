{
  lib,
  pkgs,
  ...
}:
{
  imports = [ ./minimal.nix ];

  config = {
    services.traefik.enable = lib.mkForce false;
    services.tailscale.enable = lib.mkForce false;
    systemd.services.tailscale-setup.enable = lib.mkForce false;
    # services.easytierMesh.enable = lib.mkForce false;
    services.nginx.enable = lib.mkForce false;
    # security.acme.certs = lib.mkForce { };
    security.acme.certs.main = lib.mkForce { };
    # security.acme.acceptTerms = lib.mkForce false;

    # --- 极限资源削减策略 (向 Alpine 看齐) ---

    # 1. 禁用所有监控与可观测性组件
    services.prometheus.exporters.node.enable = lib.mkForce false;
    services.prometheus.exporters.blackbox.enable = lib.mkForce false;
    services.prometheus.exporters.nix-registry.enable = lib.mkForce false;
    systemd.services.prometheus-vmagent.enable = lib.mkForce false;

    # 2. 禁用多余的网络辅助服务
    services.nscd.enable = lib.mkForce false;
    system.nssModules = lib.mkForce [ ];
    services.dnsmasq.enable = lib.mkForce false;

    # 3. 剥离无用的 systemd 核心组件
    # systemd-logind 对于只通过 ssh 无桌面登录的服务器来说非必需
    systemd.services."systemd-logind".enable = lib.mkForce false;
    # udisks2 (磁盘挂载管理) 不需要
    services.udisks2.enable = lib.mkForce false;
    # 彻底关闭系统默认 OOMD，只保留 earlyoom
    systemd.oomd.enable = lib.mkForce false;

    systemd.services.traefik-certs-dumper.enable = lib.mkForce false;
    systemd.services.networkd-dispatcher.enable = lib.mkForce false;

    # 4. 极致压缩内核常驻内存
    # 强制换回最基础的 LTS 内核，以便编译和挂载最暴力的 out-of-tree bbrv1-kmod！
    # 相比 XanMod 自带的 BBRv3，原版 bbrv1 发包更为粗暴，能在国际链路上有效抢夺带宽。
    boot.kernelPackages = lib.mkForce pkgs.linuxPackages;

    # 5. Xray 内存回收优化
    # 由于内存已经非常宽裕（目前剩余超过100M），将 GOGC 放宽至 60，
    # 减少单核 CPU 因为过于频繁的垃圾回收 (GC) 导致的上下文切换开销。
    systemd.services.xray.environment.GOGC = lib.mkForce "60";
  };
}
