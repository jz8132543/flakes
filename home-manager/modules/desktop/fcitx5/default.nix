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

  # install fcitx5 and rime
  home.packages = with pkgs; [
    fcitx5
    fcitx5-rime
    qt6Packages.fcitx5-configtool
    fcitx5-gtk
  ];

  home.sessionVariables = {
    GTK_IM_MODULE = "fcitx";
    QT_IM_MODULE = "fcitx";
    XMODIFIERS = "@im=fcitx";
  };

  # systemd user services: fcitx5 daemon and a minimal local LLM suggestion service
  systemd.user.services.fcitx5-daemon = {
    Unit = {
      Description = "fcitx5 daemon (user)";
      Wants = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.fcitx5}/bin/fcitx5";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # no AI/LLM integration configured
}
