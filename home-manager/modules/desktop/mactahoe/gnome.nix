{
  pkgs,
  lib,
  osConfig,
  ...
}:
{
  config = lib.mkIf osConfig.desktop.gnome.enable (
    import ../../../../archive/desktop/gnome/home-manager/modules/desktop/mactahoe/gnome.nix.bak {
      inherit pkgs;
    }
  );
}
