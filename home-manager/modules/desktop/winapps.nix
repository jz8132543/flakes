{
  config,
  lib,
  pkgs,
  inputs,
  osConfig ? { },
  ...
}:

let
  cfg = config.programs.winapps;
  # 根据 DPI 计算缩放
  dpi = config.wayland.dpi or 96;
  calculatedScale =
    if dpi >= 192 then
      "180"
    else if dpi >= 144 then
      "140"
    else
      "100";
  desktopScale = toString (dpi * 100 / 96);
  # 与 NixOS 模块 desktop.winapps.podman 联动（winapps 客户端由 NixOS 模块安装）
  podmanEnabled = lib.attrByPath [ "desktop" "winapps" "podman" "enable" ] false osConfig;
  # 复用 NixOS 模块生成的 compose 文件（/etc/winapps/compose.yaml 指向同一 store 路径）
  composeYaml = lib.attrByPath [ "environment" "etc" "winapps/compose.yaml" "source" ] null osConfig;
in
{
  options.programs.winapps = {
    enable = lib.mkEnableOption "WinApps Desktop Client and Autopause configuration" // {
      default = true;
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. 声明式 winapps.conf（全部使用 WinApps 官方配置项）
    home.file.".config/winapps/winapps.conf".text = ''
      # ==============================================================================
      # WINAPPS CONFIGURATION (NixOS Managed)
      # ==============================================================================
      RDP_USER="Docker"
      RDP_PASS="admin"
      RDP_DOMAIN=""
      RDP_IP="127.0.0.1"
      RDP_PORT="3390"
      WAFLAVOR="podman"

      # 动态计算的高分屏缩放 (当前 DPI: ${toString dpi}, 比例: ${desktopScale}%)
      RDP_SCALE="${calculatedScale}"

      # 可移动介质挂载路径（GNOME/udisks 默认使用 /run/media）
      REMOVABLE_MEDIA="/run/media"

      # 驱动重定向：挂载全盘根目录 / 为 \\tsclient\root，家目录为 \\tsclient\home，
      # 共享文件夹为 \\tsclient\WinAppsShare，并启用打印机/剪贴板/声卡重定向
      # - /network:lan: 本机回环低延迟模式
      # FreeRDP 3 rejects the legacy /gfx-progressive and +glyph-cache flags.
      # - /scale-desktop:${desktopScale} 与 RDP_SCALE="${calculatedScale}" 配合实现矢量级 HiDPI 缩放
      RDP_FLAGS="/cert:tofu /network:lan /gdi:hw /gfx:RFX /sound /microphone +clipboard /printer /drive:root,/ /drive:home,${config.home.homeDirectory} /drive:WinAppsShare,${config.home.homeDirectory}/Storage/WinAppsShare /scale-desktop:${desktopScale}"

      DEBUG="true"

      # ==============================================================================
      # [官方闲置自动挂起 (AUTOPAUSE)]
      # ==============================================================================
      # 当所有 Office/Windows 窗口关闭 300 秒后，WinApps 会自动通过
      # podman-compose pause 将容器置入 pause 状态，CPU 占用彻底降为 0%；
      # 下次打开 docx/xlsx/pptx 等文件时会自动 unpause 秒级恢复。
      AUTOPAUSE="on"
      AUTOPAUSE_TIME="300"
    '';

    # 2. 与 NixOS 模块生成的开机启动服务共用同一个 compose 文件，
    # 使 WinApps 官方的 pause/unpause/start 操作命中同一个容器
    home.file.".config/winapps/compose.yaml" = lib.mkIf (podmanEnabled && composeYaml != null) {
      source = composeYaml;
    };

    # WinApps resolves app metadata from ~/.local/share/winapps/apps.
    home.file.".local/share/winapps/apps".source = "${
      inputs.winapps.packages.${pkgs.stdenv.hostPlatform.system}.winapps
    }/src/apps";

    # 3. 声明式 Office 与 Windows 桌面入口
    xdg.desktopEntries = {
      winapps-word = {
        name = "Microsoft Word";
        genericName = "Word Processor";
        comment = "Microsoft Word (WinApps)";
        exec = "winapps word %F";
        icon = "ms-word";
        terminal = false;
        categories = [
          "Office"
          "WordProcessor"
        ];
        mimeType = [
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
          "application/msword"
          "application/vnd.ms-word.document.macroEnabled.12"
          "application/vnd.openxmlformats-officedocument.wordprocessingml.template"
          "application/vnd.ms-word"
          "application/msword-template"
          "application/x-msword"
          "application/rtf"
        ];
      };
      winapps-excel = {
        name = "Microsoft Excel";
        genericName = "Spreadsheet";
        comment = "Microsoft Excel (WinApps)";
        exec = "winapps excel %F";
        icon = "ms-excel";
        terminal = false;
        categories = [
          "Office"
          "Spreadsheet"
        ];
        mimeType = [
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
          "application/vnd.ms-excel"
          "application/msexcel"
          "application/x-msexcel"
          "text/csv"
        ];
      };
      winapps-powerpoint = {
        name = "Microsoft PowerPoint";
        genericName = "Presentation";
        comment = "Microsoft PowerPoint (WinApps)";
        exec = "winapps powerpoint %F";
        icon = "ms-powerpoint";
        terminal = false;
        categories = [
          "Office"
          "Presentation"
        ];
        mimeType = [
          "application/vnd.openxmlformats-officedocument.presentationml.presentation"
          "application/vnd.ms-powerpoint"
          "application/mspowerpoint"
          "application/powerpoint"
        ];
      };
      winapps-windows = {
        name = "Windows Subsystem";
        genericName = "Virtual Desktop";
        comment = "Open Full Windows Desktop Session";
        exec = "winapps windows";
        icon = "distributor-logo-windows";
        terminal = false;
        categories = [
          "System"
          "Utility"
        ];
      };
    };

    # 4. 注册协议与文档格式默认关联 (docx, xlsx, pptx 等默认由 WinApps Office 打开)
    xdg.mimeApps.defaultApplications = {
      # Microsoft Word
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = "winapps-word.desktop";
      "application/msword" = "winapps-word.desktop";
      "application/vnd.ms-word.document.macroEnabled.12" = "winapps-word.desktop";
      "application/vnd.openxmlformats-officedocument.wordprocessingml.template" = "winapps-word.desktop";
      "application/vnd.ms-word" = "winapps-word.desktop";
      "application/rtf" = "winapps-word.desktop";

      # Microsoft Excel
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = "winapps-excel.desktop";
      "application/vnd.ms-excel" = "winapps-excel.desktop";
      "application/vnd.ms-excel.sheet.macroEnabled.12" = "winapps-excel.desktop";
      "application/vnd.openxmlformats-officedocument.spreadsheetml.template" = "winapps-excel.desktop";
      "application/vnd.ms-excel.sheet.binary.macroenabled.12" = "winapps-excel.desktop";

      # Microsoft PowerPoint
      "application/vnd.openxmlformats-officedocument.presentationml.presentation" =
        "winapps-powerpoint.desktop";
      "application/vnd.ms-powerpoint" = "winapps-powerpoint.desktop";
      "application/vnd.openxmlformats-officedocument.presentationml.template" =
        "winapps-powerpoint.desktop";
      "application/vnd.openxmlformats-officedocument.presentationml.slideshow" =
        "winapps-powerpoint.desktop";

      # Protocol Handlers
      "x-scheme-handler/ms-word" = "winapps-word.desktop";
      "x-scheme-handler/ms-excel" = "winapps-excel.desktop";
      "x-scheme-handler/ms-powerpoint" = "winapps-powerpoint.desktop";
    };

    # 5. WinApps Launcher 开机自启
    systemd.user.services.winapps-launcher = {
      Unit = {
        Description = "WinApps Taskbar Launcher Widget";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${
          inputs.winapps.packages.${pkgs.stdenv.hostPlatform.system}.winapps-launcher
        }/bin/winapps-launcher";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
