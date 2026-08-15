{
  pkgs,
  ...
}:
let
  surfaceDisplayAutoPy = ./surface-display-auto.py;

  surfaceDisplayAuto = pkgs.writeShellApplication {
    name = "surface-display-auto";
    runtimeInputs = [
      pkgs.python3
      pkgs.glib
      pkgs.systemd
    ];
    text = ''
      exec ${pkgs.python3.interpreter} ${surfaceDisplayAutoPy} "$@"
    '';
  };

  surfaceDisplayDiagnose = pkgs.writeShellApplication {
    name = "surface-display-diagnose";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.glib
      pkgs.gnugrep
      pkgs.pciutils
      pkgs.ripgrep
      pkgs.systemd
      pkgs.usbutils
      surfaceDisplayAuto
    ];
    text = builtins.readFile ./surface-display-diagnose.sh;
  };

  surfaceDisplayRecover = pkgs.writeShellApplication {
    name = "surface-display-recover";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.glib
      pkgs.systemd
      surfaceDisplayAuto
      surfaceDisplayDiagnose
    ];
    text = builtins.readFile ./surface-display-recover.sh;
  };
in
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
    surfaceDisplayAuto
    surfaceDisplayDiagnose
    surfaceDisplayRecover
  ];

  # ==========================================
  # 硬件自启动服务
  # ==========================================
  systemd.user.services.surface-display-auto = {
    description = "Automatically switch Surface to external-only when an external monitor appears";
    wantedBy = [
      "default.target"
      "graphical-session.target"
    ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${surfaceDisplayAuto}/bin/surface-display-auto watch";
      Restart = "always";
      RestartSec = 2;
    };
  };
}
