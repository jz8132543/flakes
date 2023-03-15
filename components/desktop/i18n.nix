{ pkgs, ... }:
{
  i18n = {
    defaultLocale = "en_US.UTF-8";
    inputMethod = {
      enabled = "fcitx5";
      fcitx5.addons = with pkgs; [
        fcitx5-chinese-addons
        fcitx5-configtool
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

}
