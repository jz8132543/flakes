{ pkgs, path, util, ... }:
{
  home.packages = with pkgs; [
    (ark.override { unfreeEnableUnrar = true; })
    ghostwriter
    kate
    kcolorchooser
    kompare
    kdeconnect
    krita
    kteatime
    yakuake
  ];

  imports = util.importsFiles ./plasma-apps;
}
