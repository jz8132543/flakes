{ config, pkgs, ...  }:

{
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

  hardware.video.hidpi.enable = true;
}
