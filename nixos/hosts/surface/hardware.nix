{
  pkgs,
  ...
}:
{
  # ==========================================
  # Surface 核心硬件与内核配置
  # ==========================================
  hardware.microsoft-surface = {
    kernelVersion = "longterm";
  };

  nix.settings.substituters = [ "https://linux-surface.cachix.org" ];
  nix.settings.trusted-public-keys = [
    "linux-surface.cachix.org-1:QfXYqHXil6OIWq9lro4kQEnOS0qV8OmtJ2e0YcW8nKE="
  ];

  # ==========================================
  # GPU 与显示配置
  # ==========================================
  desktop.nvidia = {
    mode = "sync";
  };

  # ==========================================
  # 触屏、电源管理与驱动优化
  # ==========================================
  # 开启触屏支持
  services.iptsd.enable = true;

  # 电源管理：禁用可能导致休眠死机的 TLP，改用 power-profiles-daemon
  services.power-profiles-daemon.enable = true;
  services.tlp.enable = false;

  # 修复由于不受支持的 IPU6 摄像头导致的 Wireplumber 异常
  services.pipewire.wireplumber.extraConfig = {
    "50-surface-disable-libcamera" = {
      "monitor.libcamera" = "disabled";
      "wireplumber.profiles" = {
        main = {
          "monitor.libcamera" = "disabled";
          "hardware.video-capture" = "disabled";
        };
      };
    };
  };

  # ==========================================
  # Surface 特殊功能权限 (DTX/控制组)
  # ==========================================
  users.groups.surface-control = { };
  users.users.tippy.extraGroups = [ "surface-control" ];

  # ==========================================
  # 硬件控制与系统工具包
  # ==========================================
  environment.systemPackages = with pkgs; [
    efibootmgr
    pciutils
    usbutils
    v4l-utils

    # Surface 相关工具
    surface-control
  ];
}
