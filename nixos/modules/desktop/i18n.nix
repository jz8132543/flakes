{
  pkgs,
  config,
  ...
}:
{
  time.timeZone = "Asia/Shanghai";

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      addons = with pkgs; [
        fcitx5-gtk
        qt6Packages.fcitx5-qt
        fcitx5-rime
        qt6Packages.fcitx5-chinese-addons
        librime
        librime-lua
        librime-octagram
      ];
      # GNOME Wayland primarily integrates third-party IMEs via the ibus frontend.
      # Keep the native Wayland frontend for Plasma, where the KWin virtual keyboard
      # path is better integrated.
      waylandFrontend = config.desktop.environment == "kde";
    };
  };
}
