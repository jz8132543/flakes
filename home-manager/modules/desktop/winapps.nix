{
  config,
  lib,
  pkgs,
  inputs,
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
in
{
  options.programs.winapps = {
    enable = lib.mkEnableOption "WinApps Desktop Client and Autopause configuration" // {
      default = true;
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. 声明式 winapps.conf
    home.file.".config/winapps/winapps.conf".text = ''
      # ==============================================================================
      # WINAPPS CONFIGURATION (NixOS Managed)
      # ==============================================================================
      RDP_USER="Docker"
      RDP_PASS="docker"
      RDP_DOMAIN=""
      RDP_IP="127.0.0.1"
      WAFLAVOR="podman"

      # 动态计算的高分屏缩放 (当前 DPI: ${toString dpi}, 比例: ${desktopScale}%)
      RDP_SCALE="${calculatedScale}"

      # 驱动重定向：挂载全盘根目录 / 为 \\tsclient\root，家目录为 \\tsclient\home，共享文件夹为 \\tsclient\BottlesShare
      RDP_FLAGS="/cert:tofu /sound /microphone +clipboard /drive:root,/ /drive:home,${config.home.homeDirectory} /drive:BottlesShare,${config.home.homeDirectory}/Storage/BottlesShare /scale-desktop:${desktopScale}"

      MULTIMON="false"
      DEBUG="true"

      # ==============================================================================
      # [虚拟机电源管理策略：动态冻结 (Autopause) vs 持续常驻 (Always-On)]
      # ==============================================================================
      # 【模式 A（默认）：闲置自动冻结】
      # 当所有 Office/Windows 窗口关闭 300 秒后，自动将容器置入 pause 状态，CPU 占用彻底降为 0%
      AUTOPAUSE="on"
      AUTOPAUSE_TIME="300"

      # 【模式 B（备用）：持续常驻不暂停】
      # 如果你需要虚拟机始终保持完整活跃（例如后台需要持续接收消息通知），
      # 请注释掉上面的 AUTOPAUSE="on" 与 AUTOPAUSE_TIME，并取消下面这行的注释即可：
      # AUTOPAUSE="off"
    '';

    # 2. 声明式 Office 与 Windows 桌面入口
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

    # 3. 注册协议关联
    xdg.mimeApps.defaultApplications = {
      "x-scheme-handler/ms-word" = "winapps-word.desktop";
      "x-scheme-handler/ms-excel" = "winapps-excel.desktop";
      "x-scheme-handler/ms-powerpoint" = "winapps-powerpoint.desktop";
    };

    # 4. WinApps Launcher 开机自启
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
