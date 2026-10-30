{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.secu;
in
{
  options.programs.secu.enable =
    lib.mkEnableOption "SecU and hardware encrypted U-disk desktop support"
    // {
      default = true;
    };

  config = lib.mkIf cfg.enable {
    # 启用 SCSI generic (sg) 内核驱动，使 /dev/sg* 字符设备节点可用，
    # 供 SecU 等安全 U 盘通过 SCSI pass-through (SG_IO) 发送控制指令以识别并解锁硬件。
    boot.kernelModules = [ "sg" ];

    # 启用 envfs 提供 /bin/bash 等传统路径兼容，供 U 盘内置 autorun.sh 脚本直接执行。
    services.envfs.enable = lib.mkDefault true;

    # 预置非打补丁外部 ELF 二进制程序运行所需的共享库（nix-ld）。
    programs.nix-ld.libraries = with pkgs; [
      libxcrypt-legacy
      libGL
      glib
      dbus
      fontconfig
      freetype
      libx11
      libxext
      libxrender
      libxi
      libsm
      libice
      libxcb
      qt5.qtbase
      qt5.qtwayland
    ];

    # 系统级运行工具及 Qt 运行时检测依赖：
    # - lsb-release: autorun.sh 获取发行版标识
    # - xhost: 原始脚本调用的 X11 访问控制命令
    # - qt5.qtbase.dev: 提供 qmake，供启动器运行时自动识别宿主 Qt5 环境
    # - qt5.qtbase / qt5.qtwayland: 提供 Wayland/X11 平台插件 (libqwayland-egl 等)
    environment.systemPackages = with pkgs; [
      lsb-release
      xhost
      qt5.qtbase
      qt5.qtbase.dev
      qt5.qtwayland
    ];
  };
}
