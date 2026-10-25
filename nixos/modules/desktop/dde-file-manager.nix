{
  pkgs,
  inputs,
  lib,
  config,
  ...
}:
let
  cfg = config.programs.dde-file-manager;
  dde-pkgs = inputs.dde-nixos.legacyPackages.${pkgs.stdenv.hostPlatform.system}.deepin.overrideScope (
    _final: prev: {
      dtkwidget = prev.dtkwidget.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          # Qt 6.12 does not export the private QFont shared-pointer destructor.
          substituteInPlace src/widgets/dstyleoption.cpp \
            --replace-fail 'const auto fontD = D_PRIVATE_MEMBER(font, QFont_d_tag{});' \
              'const auto &fontD = D_PRIVATE_MEMBER(font, QFont_d_tag{});'
        '';
      });
    }
  );

  deepin-qt-theme-conf = pkgs.writeTextDir "deepin/qt-theme.ini" ''
    [Theme]
    IconThemeName=bloom
    iconThemeName=bloom
    FallbackIconThemeName=bloom
    fallbackIconThemeName=bloom
    StyleNames=chameleon
    styleNames=chameleon
    Font=Source Han Sans SC
    FontSize=10.5
    MonoFont=Noto Mono
    systemFont=Source Han Sans SC
    systemFontPointSize=10.5
    systemFixedFont=Noto Mono
  '';

  deepin-dsg-conf = pkgs.writeTextDir "share/dsg/configs/org.kde.kwin/org.kde.kwin.compositing.json" ''
    {
        "magic": "dsg.config.meta",
        "version": "1.0",
        "contents": {
            "user_type": {
                "value": 4,
                "serial": 0,
                "flags": [],
                "name": "user_type",
                "description": "window effect type: 4 disables window-behind blur and forces opaque sidebar",
                "permissions": "readwrite",
                "visibility": "public"
            }
        }
    }
  '';

  # 原生包轻量包装：仅注入自身独立环境变量与优化桌面项，完全不重编、不修改原生二进制
  dde-file-manager-wrapped = pkgs.symlinkJoin {
    name = "dde-file-manager-wrapped";
    paths = [ dde-pkgs.dde-file-manager ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
            # 包装 file-manager.sh 注入独立 Deepin 原生主题、DConfig 本地后端、DSG 目录与环境变量
            wrapProgram $out/bin/file-manager.sh \
              --set QT_QPA_PLATFORMTHEME "deepin" \
              --set QT_STYLE_OVERRIDE "chameleon" \
              --set QT_QPA_PLATFORM "wayland;xcb" \
              --set QT_QPA_SYSTEM_ICON_THEME "bloom" \
              --set DSG_DCONFIG_BACKEND_TYPE "FileBackend" \
              --set XDG_CURRENT_DESKTOP "DDE" \
              --set D_QT_THEME_CONFIG_PATH "${deepin-qt-theme-conf}" \
              --set DSG_DATA_DIRS "${deepin-dsg-conf}/share/dsg:${dde-pkgs.dde-file-manager}/share/dsg:${dde-pkgs.dtkcommon}/share/dsg:/run/current-system/sw/share/dsg" \
              --prefix XDG_DATA_DIRS : "${deepin-dsg-conf}/share:${dde-pkgs.deepin-icon-theme}/share:${dde-pkgs.deepin-desktop-theme}/share:${dde-pkgs.dtkcommon}/share:${dde-pkgs.dde-file-manager}/share:${pkgs.papirus-icon-theme}/share"

            # 包装 dde-file-manager-daemon 确保后台服务也使用 FileBackend 读取配置
            wrapProgram $out/bin/dde-file-manager-daemon \
              --set DSG_DCONFIG_BACKEND_TYPE "FileBackend" \
              --set DSG_DATA_DIRS "${deepin-dsg-conf}/share/dsg:${dde-pkgs.dde-file-manager}/share/dsg:${dde-pkgs.dtkcommon}/share/dsg:/run/current-system/sw/share/dsg" \
              --prefix XDG_DATA_DIRS : "${deepin-dsg-conf}/share:${dde-pkgs.dtkcommon}/share:${dde-pkgs.dde-file-manager}/share"

            # 让 bin/dde-file-manager 直接执行包装后的 file-manager.sh，跳过在非 DDE 环境下会被宿主接管或超时的 DBus 流程
            rm $out/bin/dde-file-manager
            cat << 'EOF' > $out/bin/dde-file-manager
      #!/bin/sh
      exec $(dirname "$0")/file-manager.sh "$@"
      EOF
            chmod +x $out/bin/dde-file-manager

            # 1. 修复并暴露 dde-computer.desktop（“计算机 / 此电脑”快捷方式）
            rm $out/share/applications/dde-computer.desktop
            cat ${dde-pkgs.dde-file-manager}/share/applications/dde-computer.desktop > $out/share/applications/dde-computer.desktop
            # 移除 OnlyShowIn=Deepin;DDE，使其在 GNOME 等所有桌面的搜索与应用抽屉中可见
            sed -i '/OnlyShowIn=/d' $out/share/applications/dde-computer.desktop
            # 确保直接通过包装后的 dde-file-manager 打开 computer:/// 磁盘与设备视图
            sed -i "s|^Exec=.*|Exec=$out/bin/dde-file-manager computer:///|" $out/share/applications/dde-computer.desktop
            # 补全搜索关键词（支持：计算机、此电脑、我的电脑、电脑、computer、dde 等）
            echo "Keywords=computer;dde;deepin;files;manager;计算机;电脑;我的电脑;此电脑;设备;" >> $out/share/applications/dde-computer.desktop
            echo "Keywords[zh_CN]=computer;dde;deepin;files;manager;计算机;电脑;我的电脑;此电脑;设备;" >> $out/share/applications/dde-computer.desktop

            # 2. 修正 dde-file-manager.desktop（文件管理器）
            rm $out/share/applications/dde-file-manager.desktop
            cat ${dde-pkgs.dde-file-manager}/share/applications/dde-file-manager.desktop > $out/share/applications/dde-file-manager.desktop
            sed -i "s|^Exec=.*dde-file-manager|Exec=$out/bin/dde-file-manager|" $out/share/applications/dde-file-manager.desktop
            sed -i 's/^Name\[zh_CN\]=.*/Name[zh_CN]=深度文件管理器/' $out/share/applications/dde-file-manager.desktop
            echo "Keywords=dde;deepin;file;files;manager;深度;文件管理器;" >> $out/share/applications/dde-file-manager.desktop
            echo "Keywords[zh_CN]=dde;deepin;file;files;manager;深度;文件管理器;文件;" >> $out/share/applications/dde-file-manager.desktop
    '';
  };
in
{
  options.programs.dde-file-manager.enable = lib.mkEnableOption "DDE File Manager" // {
    default = true;
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      dde-file-manager-wrapped
      dde-pkgs.deepin-icon-theme
      dde-pkgs.deepin-desktop-theme
      dde-pkgs.dtkcommon
      pkgs.papirus-icon-theme
      deepin-dsg-conf
    ];

    # 链接 DSG、Deepin 资源与主题目录，供 DTK 识别 preference 和主题资源
    environment.pathsToLink = [
      "/share/dsg"
      "/share/deepin"
      "/share/deepin-themes"
    ];

    # 基础文件管理挂载支持
    services.gvfs.enable = true;
  };
}
