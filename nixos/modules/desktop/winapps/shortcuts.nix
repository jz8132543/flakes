{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.winapps;

  # 单个 Windows 快捷方式的类型声明
  shortcutType = lib.types.submodule (
    { name, ... }: {
      options = {
        enable = lib.mkEnableOption "this WinApps shortcut" // {
          default = true;
        };

        desktopName = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Display name shown in application menus and desktop entries.";
        };

        genericName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Generic application description (e.g. 'AI Assistant').";
        };

        comment = lib.mkOption {
          type = lib.types.str;
          default = "Run ${name} seamlessly via WinApps";
          description = "Tooltip description shown on hover.";
        };

        winExecutable = lib.mkOption {
          type = lib.types.str;
          description = ''
            Windows guest executable path (e.g. 'C:\Users\Docker\AppData\Local\Programs\Doubao\Doubao.exe').
          '';
        };

        icon = lib.mkOption {
          type = lib.types.str;
          default = "application-x-executable";
          description = "Icon name from the current icon theme or an absolute path.";
        };

        categories = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "Utility" ];
          description = "XDG categories for desktop menu placement.";
        };

        mimeType = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "List of MIME types this application can open.";
        };

        keywords = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Search keywords for desktop application launchers.";
        };

        terminal = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether the application should run in a terminal window.";
        };
      };
    }
  );

  # 为每个启用的快捷方式生成独立的软件包（包含包装脚本与 .desktop 文件）
  mkShortcutPackage =
    id: s:
    let
      binName = "winapps-${id}";

      # 包装脚本：确保 ~/.local/share/winapps/apps/<id>/info 始终最新，
      # 然后透明调用 winapps，复用其自动唤醒、挂起、文件路径转换与并发锁机制。
      launcher = pkgs.writeShellScript binName ''
                set -eu
                appDir="''${HOME}/.local/share/winapps/apps/${id}"
                infoFile="''${appDir}/info"
                mkdir -p "''${appDir}"

                cat > "''${infoFile}" << 'EOF'
        NAME="${s.desktopName}"
        FULL_NAME="${s.desktopName}"
        WIN_EXECUTABLE="${s.winExecutable}"
        CATEGORIES="${lib.concatStringsSep ";" s.categories};"
        MIME_TYPES="${lib.concatStringsSep ";" s.mimeType}${lib.optionalString (s.mimeType != [ ]) ";"}"
        ICON="${s.icon}"
        EOF

                exec ${cfg.package}/bin/winapps "${id}" "$@"
      '';

      desktopItem = pkgs.makeDesktopItem {
        name = binName;
        inherit (s) desktopName;
        inherit (s) genericName;
        inherit (s) comment;
        exec = "${launcher} %F";
        inherit (s) icon;
        inherit (s) terminal;
        inherit (s) categories;
        inherit (s) keywords;
        mimeTypes = s.mimeType;
        startupWMClass = s.desktopName;
      };
    in
    pkgs.symlinkJoin {
      name = "winapps-shortcut-${id}";
      paths = [
        (pkgs.runCommand "winapps-bin-${id}" { } ''
          mkdir -p $out/bin
          ln -s ${launcher} $out/bin/${binName}
          ln -s ${launcher} $out/bin/${id}-winapps
        '')
        desktopItem
      ];
    };

  enabledShortcuts = lib.filterAttrs (_: s: s.enable) cfg.shortcuts;
in
{
  options.programs.winapps.shortcuts = lib.mkOption {
    type = lib.types.attrsOf shortcutType;
    default = { };
    description = ''
      Declarative Windows application shortcuts managed by WinApps.
      Each entry automatically generates an XDG desktop entry and CLI wrapper.
    '';
  };

  config = lib.mkIf cfg.enable {
    # 默认预置快捷方式：为用户自装的豆包桌面版提供开箱即用的声明式支持
    programs.winapps.shortcuts = {
      doubao = {
        desktopName = lib.mkDefault "豆包";
        genericName = lib.mkDefault "AI 智能助手";
        comment = lib.mkDefault "字节跳动豆包桌面版 (Windows/WinApps 工作模式)";
        winExecutable = lib.mkDefault ''C:\Users\Docker\AppData\Local\Doubao\Application\Doubao.exe'';
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
    };

    # 将所有启用的快捷方式包全量注册进系统环境
    environment.systemPackages = lib.mapAttrsToList mkShortcutPackage enabledShortcuts;
  };
}
