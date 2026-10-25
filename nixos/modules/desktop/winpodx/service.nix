{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.winpodx;
in
{
  config = lib.mkIf cfg.enable {
    # 将运行用户加入 kvm 组，确保硬件虚拟化直通
    users.users.${cfg.userName}.extraGroups = [
      "kvm"
    ];

    # 安装 WinPodX 核心 CLI 工具及配套依赖
    environment.systemPackages = [
      cfg.package
      pkgs.freerdp
      pkgs.libnotify
      pkgs.podman-compose
      pkgs.wmctrl
    ];

    # Only the configured KVM group needs device access.
    services.udev.extraRules = ''
      KERNEL=="kvm", GROUP="kvm", MODE="0660"
    '';
  };
}
