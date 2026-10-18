{
  pkgs,
  inputs,
  ...
}:
let
  dde-pkgs = inputs.dde-nixos.legacyPackages.${pkgs.stdenv.hostPlatform.system}.deepin;

  # 原生包轻量包装：仅注入自身独立环境变量与优化桌面项，完全不重编、不修改原生二进制
  dde-file-manager-wrapped = pkgs.symlinkJoin {
    name = "dde-file-manager-wrapped";
    paths = [ dde-pkgs.dde-file-manager ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      # 仅给 dde-file-manager 独立注入 Deepin 原生主题环境变量，隔离系统其他 Qt 程序
      wrapProgram $out/bin/dde-file-manager \
        --set QT_QPA_PLATFORMTHEME "deepin" \
        --set QT_STYLE_OVERRIDE "chameleon" \
        --set QT_QPA_PLATFORM "wayland;xcb" \
        --prefix XDG_DATA_DIRS : "${dde-pkgs.deepin-icon-theme}/share:${dde-pkgs.deepin-desktop-theme}/share:${dde-pkgs.dtkcommon}/share"

      wrapProgram $out/bin/file-manager.sh \
        --set QT_QPA_PLATFORMTHEME "deepin" \
        --set QT_STYLE_OVERRIDE "chameleon" \
        --set QT_QPA_PLATFORM "wayland;xcb" \
        --prefix XDG_DATA_DIRS : "${dde-pkgs.deepin-icon-theme}/share:${dde-pkgs.deepin-desktop-theme}/share:${dde-pkgs.dtkcommon}/share"

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
  environment.systemPackages = [
    dde-file-manager-wrapped
    dde-pkgs.deepin-icon-theme
    dde-pkgs.deepin-desktop-theme
    dde-pkgs.dtkcommon
  ];

  # 链接 DSG 配置目录，供 DTK 识别 preference
  environment.pathsToLink = [ "/share/dsg" ];

  # 启用底层后台服务与文件系统挂载支持
  services.dbus.packages = [ dde-pkgs.dde-file-manager ];
  systemd.packages = [ dde-pkgs.dde-file-manager ];
  systemd.user.services.dde-file-manager.wantedBy = [ "default.target" ];
  services.gvfs.enable = true;
}
