{ config, pkgs, lib, ... }:

lib.mkIf config.environment.graphical.enable{
  i18n = {
    defaultLocale = "en_US.UTF-8";
    inputMethod = {
      enabled = "fcitx5";
      fcitx5.addons = with pkgs; [
        fcitx5-chinese-addons
        #fcitx5-configtool

        fcitx5-gtk
        libsForQt5.fcitx5-qt
        fcitx5-rime
        rime-data
        nur.repos.xddxdd.rime-zhwiki
        nur.repos.xddxdd.rime-aurora-pinyin
        nur.repos.xddxdd.rime-dict
        nur.repos.xddxdd.rime-moegirl
      ];
    };
  };
  environment.variables = {
    GTK_IM_MODULE = "fcitx";
    QT_IM_MODULE = "fcitx";
    XMODIFIERS = "@im=fcitx";
    INPUT_METHOD = "fcitx";
    SDL_IM_MODULE = "fcitx";
    GLFW_IM_MODULE = "fcitx";
    NIX_RIME_DATA = "/run/current-system/sw/share/rime-data";
  };

  systemd.user.services.fcitx5-daemon.environment = {
    NIX_RIME_DATA = "/run/current-system/sw/share/rime-data";
  };
  environment.global-persistence.user.directories = [
    ".config/fcitx5"
    ".local/share/fcitx5/rime"
  ];
}
