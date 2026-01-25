{ config, ... }:
let
  currentIM = config.i18n.inputMethod.enabled;

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
  services.flatpak = {
    packages = [
      # 1. Bottles 主程序
      # "com.usebottles.bottles"
      # 用于图形化管理 Flatpak 的权限（如允许微信访问 ~/Downloads）
      # "com.github.tchx84.flatseal"
    ];
    overrides = {
      "global" = {
        environment = imEnv // {
          # "GTK_THEME" = "Gruvbox-Dark";
          "GTK_APPLICATION_PREFER_DARK_THEME" = "1";
        };

        Context = {
          devices = [
            "dri"
            "!shm"
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
            "/nix/store:ro"

            # 用户目录资源
            "~/.local/share/fonts:ro"
            "~/.local/share/icons:ro"
            "~/.local/share/themes:ro"
            "~/.local/share/applications"

            # 系统 XDG 资源
            "xdg-config/gtk-3.0:ro"
            "xdg-config/gtk-4.0:ro"
            "xdg-data/themes:ro"
            "xdg-data/icons:ro"
          ];
        };
      };
    };
  };
}
