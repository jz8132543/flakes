{ pkgs, ... }:
{
  time.timeZone = "Asia/Shanghai";

  i18n.defaultLocale = "zh_CN.UTF-8";

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      addons = with pkgs; [
        fcitx5-rime
        librime
        librime-lua
        librime-octagram
      ];
      waylandFrontend = true;
    };
  };
}
