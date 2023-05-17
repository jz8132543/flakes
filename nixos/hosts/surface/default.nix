{ self, nixosModules, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.desktop.all
    ++ [
      ./hardware-configuration.nix
    ];
}
