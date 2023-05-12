{ self, nixosModules, ... }:
{
  imports = [
    nixosModules.base.all
    ./hardware-configuration.nix
  ];
}
