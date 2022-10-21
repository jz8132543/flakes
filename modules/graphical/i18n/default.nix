{ config, pkgs, lib, ... }:

lib.mkIf config.environment.graphical.enable{
  i18n = {
    defaultLocale = "en_US.UTF-8";
    inputMethod = {
      enabled = "fcitx5";
      fcitx5.addons = with pkgs; [
        fcitx5-chinese-addons
        fcitx5-configtool
      ];
    };
  };
  environment.global-persistence.user.directories = [
    ".config/fcitx5"
  ];
}
