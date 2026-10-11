{
  pkgs,
  inputs,
  ...
}:
let
  dde-pkgs = inputs.dde-nixos.legacyPackages.${pkgs.stdenv.hostPlatform.system}.deepin;

  # 修复 dde-file-manager 的 DBus 调用问题
  # 原脚本调用不存在的 Open 方法，应使用 ShowFolders
  dde-file-manager-fixed =
    pkgs.runCommandLocal "dde-file-manager-fixed"
      {
        inherit (dde-pkgs.dde-file-manager) name;
        nativeBuildInputs = [ pkgs.makeWrapper ];
      }
      ''
        mkdir -p $out/bin
        cp ${dde-pkgs.dde-file-manager}/bin/dde-file-manager $out/bin/dde-file-manager
        substituteInPlace $out/bin/dde-file-manager \
          --replace-fail 'org.freedesktop.FileManager1.Open' 'org.freedesktop.FileManager1.ShowFolders' \
          --replace-fail 'array:string:"$dbus_args_str"' 'array:string:"$dbus_args_str" string:""'
        wrapProgram $out/bin/dde-file-manager \
          --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.coreutils ]}
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
