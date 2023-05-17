{ self, nixosModules, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ]
  ++ nixosModules.cloud.all
  ++ nixosModules.users.tippy.all
  ++ nixosModules.services.traefik.all
  ++ nixosModules.services.headscale.all;
}
