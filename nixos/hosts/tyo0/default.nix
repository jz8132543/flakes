{ nixosModules, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.optimize.minimal
      # nixosModules.services.traefik
      # nixosModules.services.derp
      (import nixosModules.services.xray {
      })
    ];

}
