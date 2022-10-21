{ nixosConfig, config, lib, pkgs, ...  }:

lib.mkIf nixosConfig.environment.graphical.enable {
  gtk = {
    enable = true;
    theme = {
      package = pkgs.libsForQt5.breeze-gtk;
      name = "Breeze";
    };
    cursorTheme = {
      package = pkgs.libsForQt5.breeze-qt5;
      name = "breeze_cursors";
    };
    iconTheme = {
      package = pkgs.libsForQt5.breeze-qt5;
      name = "Breeze_Snow";
    };
    # font = {
    #   package = pkgs.roboto;
    #   name = "Roboto";
    #   size = 11;
    # };
    gtk2.configLocation = "${config.xdg.configHome}/gtk-2.0/gtkrc";
  };

  qt = {
    enable = true;
    # platformTheme = "gtk";
    style = {
      package = pkgs.libsForQt5.breeze-qt5;
      name = "BreezeLight";
    };
  };

  home.packages = with pkgs; [
    dconf 
    swaylock
    swaynotificationcenter
    tdesktop
    thunderbird
    wl-clipboard
    # sioyek
    #nur.repos.rewine.v2raya
  ];
  home.global-persistence = {
    directories = [
      ".thunderbird"
      ".local/share/TelegramDesktop"
    ];
  };

}
