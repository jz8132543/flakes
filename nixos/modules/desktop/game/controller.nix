{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.gamepad;
in
{
  options = {
    desktop.gamepad = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable gamepad support, udev access rules, and InputPlumber daemon.";
      };

      target = lib.mkOption {
        type = lib.types.enum [
          "ds5"
          "ds5-edge"
          "xb360"
          "xbox-elite"
          "deck"
        ];
        default = "ds5";
        description = ''
          Target controller type to emulate in InputPlumber.
          Default is `ds5` (Sony PlayStation 5 DualSense) for native gyro aiming and PS glyphs.
        '';
      };

      users = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "tippy" ];
        description = "List of user accounts to add to input and uinput groups for gamepad access.";
      };
    };

    # 兼容 modules.desktop.game.gamepad 命名规范
    modules.desktop.game.gamepad = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Alias for desktop.gamepad.enable.";
      };
    };
  };

  config = lib.mkIf (cfg.enable || config.modules.desktop.game.gamepad.enable) {
    # 1. 确保内核加载虚拟输入所需模块（InputPlumber 虚拟 DualSense 依赖 uhid）
    boot.kernelModules = [
      "uinput"
      "uhid"
    ];

    # 启用 /dev/uinput 支持并自动创建 uinput 用户组与基础节点权限
    hardware.uinput.enable = true;

    # 2. 引入社区设备规则与 InputPlumber 自带 udev 规则
    services.udev.packages = [
      pkgs.game-devices-udev-rules
      pkgs.inputplumber
    ];

    # 3. 针对飞智 (Flydigi) 系列手柄（八爪鱼 4、黑武士等，涵盖 2.4G 接收器与 Type-C 有线模式）的专用 udev 规则
    # Vendor ID 说明：
    # - 04b4: Cypress 半导体（飞智 2.4G 接收器及部分有线模式使用的 Vendor ID）
    # - 37d7: 深圳市飞智电子科技有限公司（飞智自研芯片固件及蓝牙/有线 Vendor ID）
    services.udev.extraRules = ''
      # 赋予非 root 用户对飞智手柄原始 hidraw 节点的读写权限，避免内核驱动独占，确保用户态 InputPlumber 能直接捕获并拦截原始报文
      KERNEL=="hidraw*", ATTRS{idVendor}=="04b4", MODE="0660", TAG+="uaccess", ENV{ID_INPUT_JOYSTICK}="1"
      KERNEL=="hidraw*", ATTRS{idVendor}=="37d7", MODE="0660", TAG+="uaccess", ENV{ID_INPUT_JOYSTICK}="1"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="04b4", MODE="0660", TAG+="uaccess"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="37d7", MODE="0660", TAG+="uaccess"
    '';

    # 4. 系统环境软件包（诊断工具与核心组件）
    environment.systemPackages = with pkgs; [
      inputplumber
      evtest
    ];

    # 启用 D-Bus 接口配置，确保客户端和桌面环境可正常与 InputPlumber 通信
    services.dbus.packages = [ pkgs.inputplumber ];

    # 5. InputPlumber 后台常驻守护进程
    # 注意：上游 inputplumber.service 默认硬编码 ExecStart=/usr/bin/inputplumber，在 NixOS 上需显式指定 Nix Store 路径
    systemd.services.inputplumber = {
      description = "InputPlumber Gamepad Mapping Daemon";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "systemd-udevd.service"
      ];
      wants = [ "systemd-udevd.service" ];
      serviceConfig = {
        Type = "dbus";
        BusName = "org.shadowblip.InputPlumber";
        ExecStart = "${pkgs.inputplumber}/bin/inputplumber run";
        Restart = "on-failure";
        RestartSec = "3s";
        ProtectSystem = "full";
      };
    };

    # 6. 声明式下发飞智八爪鱼 4 的 CompositeDevice 映射配置，默认将目标设备设定为 DualSense (ds5)
    environment.etc."inputplumber/devices.d/60-flydigi_apex_4.yaml".text = ''
      # yaml-language-server: $schema=https://raw.githubusercontent.com/ShadowBlip/InputPlumber/main/rootfs/usr/share/inputplumber/schema/composite_device_v1.json
      version: 1
      kind: CompositeDevice
      name: flydigi-apex-4
      matches: []
      maximum_sources: 5

      source_devices:
        - group: gamepad
          udev:
            attributes:
              - name: idVendor
                value: "04b4|37d7"
              - name: bInterfaceNumber
                value: "02"
            subsystem: hidraw
        - group: gamepad
          unique: false
          blocked: true
          udev:
            attributes:
              - name: idVendor
                value: "04b4|37d7"
            sys_name: "event*"
            subsystem: input

      target_devices:
        - ${cfg.target}
        - touchpad

      capability_map_id: flydigi-vader-4-pro

      options:
        auto_manage: false
    '';

    # 7. 确保手柄用户自动归属于 input 与 uinput 附加组
    users.users = lib.genAttrs cfg.users (_user: {
      extraGroups = [
        "input"
        "uinput"
      ];
    });
  };
}
