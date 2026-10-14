{
  pkgs,
  inputs,
  ...
}:
let
  dde-pkgs = inputs.dde-nixos.legacyPackages.${pkgs.stdenv.hostPlatform.system}.deepin;

  # 修复 dde-file-manager 的 DBus 调用问题，并保留完整的 desktop 与 icon 资源
  dde-file-manager-fixed =
    pkgs.runCommandLocal "dde-file-manager-fixed"
      {
        inherit (dde-pkgs.dde-file-manager) name;
        nativeBuildInputs = [ pkgs.makeWrapper ];
      }
      ''
        mkdir -p $out
        cp -a ${dde-pkgs.dde-file-manager}/* $out/
        chmod -R u+w $out
        substituteInPlace $out/bin/dde-file-manager \
          --replace-fail 'org.freedesktop.FileManager1.Open' 'org.freedesktop.FileManager1.ShowFolders' \
          --replace-fail 'array:string:"$dbus_args_str"' 'array:string:"$dbus_args_str" string:""'
        wrapProgram $out/bin/dde-file-manager \
          --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.coreutils ]}:$out/bin

        # 修复 desktop 文件中的 Exec 绝对路径，使其指向 Nix 包装后的二进制
        substituteInPlace $out/share/applications/dde-file-manager.desktop \
          --replace-fail '/usr/bin/dde-file-manager' "$out/bin/dde-file-manager"

        # 添加搜索关键字，支持在应用搜索中通过 dde、deepin、文件、深度 等关键词检索
        echo "Keywords=dde;deepin;file;files;manager;" >> $out/share/applications/dde-file-manager.desktop
        echo "Keywords[zh_CN]=dde;deepin;文件;文件管理器;深度;" >> $out/share/applications/dde-file-manager.desktop

        # 拷贝 SVG 图标到标准 hicolor 路径，确保 GNOME Dock 和启动器可以正确渲染图标
        mkdir -p $out/share/icons/hicolor/scalable/apps
        cp $out/share/deepin-manual/manual-assets/application/dde-file-manager/file-manager/common/dde-file-manager.svg \
          $out/share/icons/hicolor/scalable/apps/dde-file-manager.svg
      '';
in
{
  # 安装修复后的 dde-file-manager 包
  environment.systemPackages = [
    dde-file-manager-fixed
  ];

  # 启用 dde-file-manager 所需的 DBus 服务
  services.dbus.packages = [ dde-pkgs.dde-file-manager ];

  # 启用必要的 systemd 服务（dde-file-manager 的后台服务）
  systemd.packages = [ dde-pkgs.dde-file-manager ];

  # 确保 dde-file-manager daemon 在用户登录时自动启动
  systemd.user.services.dde-file-manager.wantedBy = [ "default.target" ];

  # 确保 GVFS 启用（用于文件管理器的挂载和设备访问）
  services.gvfs.enable = true;

  # 设置环境变量以避免 DBus 超时
  environment.sessionVariables = {
    # DBUS_SESSION_BUS_ADDRESS = "unix:path=$XDG_RUNTIME_DIR/bus";
  };
}
