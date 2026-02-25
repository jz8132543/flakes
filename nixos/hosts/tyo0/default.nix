{ nixosModules, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.small
      nixosModules.services.traefik
      nixosModules.services.derp
      (import nixosModules.services.xray {
      })

    ];
}
