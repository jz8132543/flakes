{
  pkgs,
  inputs,
  ...
}:
let
  dde-pkgs = inputs.dde-nixos.legacyPackages.${pkgs.stdenv.hostPlatform.system}.deepin;
in
{
  # 安装 dde-file-manager 包
  environment.systemPackages = [
    dde-pkgs.dde-file-manager
  ];

  # 启用 dde-file-manager 所需的 DBus 服务
  services.dbus.packages = [ dde-pkgs.dde-file-manager ];

  # 启用必要的 systemd 服务（dde-file-manager 的后台服务）
  systemd.packages = [ dde-pkgs.dde-file-manager ];

  # 确保 GVFS 启用（用于文件管理器的挂载和设备访问）
  services.gvfs.enable = true;

  # 设置环境变量以避免 DBus 超时
  environment.sessionVariables = {
    DBUS_SESSION_BUS_ADDRESS = "unix:path=$XDG_RUNTIME_DIR/bus";
  };
}
