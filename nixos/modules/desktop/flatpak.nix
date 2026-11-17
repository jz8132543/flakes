{ config, pkgs, ... }:
let
  currentIM = config.i18n.inputMethod.type;

  # 2. 逻辑分支：根据读取到的结果生成对应的变量集
  imEnv =
    if currentIM == "fcitx5" then
      {
        "GTK_IM_MODULE" = "fcitx"; # 注意：Fcitx5 的变量值依然是 "fcitx"
        "QT_IM_MODULE" = "fcitx";
        "XMODIFIERS" = "@im=fcitx";
        "SDL_IM_MODULE" = "fcitx";
      }
    else if currentIM == "ibus" then
      {
        "GTK_IM_MODULE" = "ibus";
        "QT_IM_MODULE" = "ibus";
        "XMODIFIERS" = "@im=ibus";
        "SDL_IM_MODULE" = "ibus";
      }
    else
      {
        # Fallback：如果未检测到常用输入法，保持为空，避免污染环境
      };
in
{
  xdg.icons.enable = true;
  xdg.sounds.enable = true;
  # Desktop profiles own portal selection; each compositor adds its own backend.
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  xdg.portal.config.common.default = "*";
  services.flatpak = {
    enable = true;
    packages = [
      # 用于图形化管理 Flatpak 的权限（如允许微信访问 ~/Downloads）
      "com.github.tchx84.Flatseal"
    ];
    overrides = {
      "global" = {
        environment = imEnv;

        Context = {
          devices = [
            "dri"
            # "shm" is required by Wine/modern apps
            "!kvm"
            "!all"
            "!usb"
            "!input"
          ];
          features = [
            "!devel"
            "!multiarch"
            "!bluetooth"
            "!canbus"
            "!per-app-dev-shm"
          ];
          shared = [ "!ipc" ];
          sockets = [
            "wayland"
            "x11"
            "fallback-x11"
            "pulseaudio"
            "!session-bus"
            "!system-bus"
            "!pcsc"
            "!cups"
            "!ssh-auth"
            "!gpg-agent"
          ];
          filesystems = [
            "~/.local/share/applications"
          ];
        };
      };
    };
  };
}
