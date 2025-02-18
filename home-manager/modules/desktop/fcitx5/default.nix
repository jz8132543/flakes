{
  config,
  lib,
  pkgs,
  ...
}:
{
  xdg = {
    configFile."fcitx5" = {
      source = ./_config;
      recursive = true;
    };
    dataFile = {
      "fcitx5/themes".source = "${pkgs.nur.repos.xddxdd.fcitx5-breeze}/share/fcitx5/themes";
    };
  };
  gtk = {
    gtk2.extraConfig = ''
      gtk-im-module="fcitx"
    '';
    gtk3.extraConfig = {
      gtk-im-module = "fcitx";
    };
    gtk4.extraConfig = {
      gtk-im-module = "fcitx";
    };
  };
  home.activation.removeExistingFcitx5Profile = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    rm -f "${config.xdg.configHome}/fcitx5/profile"
    rm -f "${config.xdg.configHome}/fcitx5/config"
  '';
}
