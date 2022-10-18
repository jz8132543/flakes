{ nixosConfig, lib, pkgs, ...  }:

lib.mkIf nixosConfig.environment.graphical.enable {
  gtk = {
    enable = true;
    theme = {
      package = pkgs.sweet;
      name = "Sweet";
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
