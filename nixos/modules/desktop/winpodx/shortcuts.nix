{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.winpodx;

  # 生成单个快捷方式的 derivation（包含 CLI 包装器与 XDG desktop 文件）
  mkShortcutPackage =
    id: s:
    let
      binName = "winpodx-${id}";

      # 包装脚本：透明调用 winpodx app run，支持自动按需唤醒、双向传参
      launcher = pkgs.writeShellScript binName ''
        set -eu
        export WINPODX_NO_TRAY_SPAWN=1
        export WINPODX_DECLARATIVE_SHORTCUTS=1
        exec ${cfg.package}/bin/winpodx app run ${lib.escapeShellArg s.slug} "$@"
      '';

      desktopItem = pkgs.makeDesktopItem {
        name = binName;
        inherit (s) desktopName;
        inherit (s) genericName;
        inherit (s) comment;
        exec = "${launcher}" + lib.optionalString (s.slug != "desktop") " %f";
        inherit (s) icon;
        inherit (s) terminal;
        inherit (s) categories;
        inherit (s) keywords;
        mimeTypes = s.mimeType;
        startupWMClass = s.wmClass;
      };
    in
    pkgs.symlinkJoin {
      name = "winpodx-shortcut-${id}";
      paths = [
        (pkgs.runCommand "winpodx-bin-${id}" { } ''
          mkdir -p $out/bin
          ln -s ${launcher} $out/bin/${binName}
          ln -s ${launcher} $out/bin/${id}-winpodx
        '')
        desktopItem
      ];
    };

  enabledShortcuts = lib.filterAttrs (_: s: s.enable) cfg.shortcuts;
in
{
  config = lib.mkIf cfg.enable {
    assertions = lib.mapAttrsToList (id: _: {
      assertion = builtins.match "[A-Za-z0-9_-]+" id != null;
      message = "WinPodX shortcut IDs must contain only ASCII letters, digits, underscores or hyphens.";
    }) enabledShortcuts;
    # 预置常用官方与第三方高频软件快捷方式
    programs.winpodx.shortcuts = {
      # 1. 豆包桌面版（AI 工作模式）
      doubao = {
        desktopName = lib.mkDefault "豆包";
        genericName = lib.mkDefault "AI 智能助手";
        comment = lib.mkDefault "字节跳动豆包桌面版 (WinPodX 工作模式)";
        slug = lib.mkDefault "doubao";
        icon = lib.mkDefault "doubao-desktop";
        categories = lib.mkDefault [
          "Utility"
          "Chat"
          "Network"
        ];
        keywords = lib.mkDefault [
          "doubao"
          "豆包"
          "ai"
          "chat"
          "bytedance"
        ];
      };

      # 2. Microsoft Word
      word = {
        executable = lib.mkDefault ''C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE'';
        wmClass = lib.mkDefault "winword";
        desktopName = lib.mkDefault "Microsoft Word";
        genericName = lib.mkDefault "文字处理软件";
        comment = lib.mkDefault "Microsoft Word (WinPodX)";
        slug = lib.mkDefault "word";
        icon = lib.mkDefault "x-office-document";
        categories = lib.mkDefault [
          "Office"
          "WordProcessor"
        ];
        mimeType = lib.mkDefault [
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
          "application/msword"
          "application/vnd.ms-word.document.macroEnabled.12"
          "application/vnd.openxmlformats-officedocument.wordprocessingml.template"
          "application/rtf"
        ];
        keywords = lib.mkDefault [
          "word"
          "doc"
          "docx"
          "office"
        ];
      };

      # 3. Microsoft Excel
      excel = {
        executable = lib.mkDefault ''C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE'';
        desktopName = lib.mkDefault "Microsoft Excel";
        genericName = lib.mkDefault "电子表格软件";
        comment = lib.mkDefault "Microsoft Excel (WinPodX)";
        slug = lib.mkDefault "excel";
        icon = lib.mkDefault "x-office-spreadsheet";
        categories = lib.mkDefault [
          "Office"
          "Spreadsheet"
        ];
        mimeType = lib.mkDefault [
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
          "application/vnd.ms-excel"
          "application/vnd.ms-excel.sheet.macroEnabled.12"
          "text/csv"
        ];
        keywords = lib.mkDefault [
          "excel"
          "xls"
          "xlsx"
          "csv"
          "office"
        ];
      };

      # 4. Microsoft PowerPoint
      powerpoint = {
        executable = lib.mkDefault ''C:\Program Files\Microsoft Office\root\Office16\POWERPNT.EXE'';
        wmClass = lib.mkDefault "powerpnt";
        desktopName = lib.mkDefault "Microsoft PowerPoint";
        genericName = lib.mkDefault "演示文稿软件";
        comment = lib.mkDefault "Microsoft PowerPoint (WinPodX)";
        slug = lib.mkDefault "powerpoint";
        icon = lib.mkDefault "x-office-presentation";
        categories = lib.mkDefault [
          "Office"
          "Presentation"
        ];
        mimeType = lib.mkDefault [
          "application/vnd.openxmlformats-officedocument.presentationml.presentation"
          "application/vnd.ms-powerpoint"
        ];
        keywords = lib.mkDefault [
          "powerpoint"
          "ppt"
          "pptx"
          "office"
        ];
      };

      # 5. Windows 完整桌面会话
      desktop = {
        desktopName = lib.mkDefault "Windows 虚拟桌面";
        genericName = lib.mkDefault "完整桌面会话";
        comment = lib.mkDefault "打开 Windows 完整虚拟机桌面 (WinPodX)";
        slug = lib.mkDefault "desktop";
        icon = lib.mkDefault "computer";
        categories = lib.mkDefault [ "Utility" ];
        keywords = lib.mkDefault [
          "windows"
          "desktop"
          "rdp"
        ];
      };
    };

    # 将生成的快捷方式包挂载进系统环境
    environment.systemPackages = lib.mapAttrsToList mkShortcutPackage enabledShortcuts;
  };
}
