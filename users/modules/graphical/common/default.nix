{ nixosConfig, config, lib, pkgs, ...  }:

lib.mkIf nixosConfig.environment.graphical.enable {
  gtk = {
    enable = true;
    theme = {
      package = pkgs.materia-theme;
      name = "Materia-light";
    };
    cursorTheme = {
      package = pkgs.gnome.adwaita-icon-theme;
      name = "Adwaita";
      size = 38;
    };
    iconTheme = {
      package = pkgs.numix-icon-theme-circle;
      name = "Numix-Circle";
    };
    font = {
      package = pkgs.roboto;
      name = "Roboto";
      size = 11;
    };
    gtk2.configLocation = "${config.xdg.configHome}/gtk-2.0/gtkrc";
  };

  qt = {
    enable = true;
    platformTheme = "gtk";
  };

  home.packages = with pkgs; [
    dconf 
    swaylock
    tdesktop
    #nur.repos.rewine.v2raya
  ];
}
