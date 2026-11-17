{
  config,
  pkgs,
  lib,
  nixosModules,
  ...
}:
let
  legacy = import ../../../archive/desktop/gnome/nixos/modules/desktop/gnome.nix.bak {
    inherit pkgs lib nixosModules;
  };
in
{
  imports = legacy.imports ++ [
    ../../../archive/desktop/gnome/nixos/hosts/surface/gnome-legacy.nix.bak
    ../../../archive/desktop/gnome/nixos/modules/desktop/portals.nix.bak
  ];
  config = lib.mkIf config.desktop.gnome.enable legacy.config;
}
