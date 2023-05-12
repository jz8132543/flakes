{ self, nixosModules, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ] ++
  nixosModules.cloud.all;
}
