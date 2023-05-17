{ config, nixosModules, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ]
  ++ nixosModules.cloud.all
  ++ nixosModules.users.tippy.all
  ++ nixosModules.desktop.all;
}
