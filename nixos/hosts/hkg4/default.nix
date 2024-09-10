{
  nixosModules,
  lib,
  ...
}:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      nixosModules.services.derp
      nixosModules.services.proxy
      nixosModules.services.tuic
      nixosModules.services.searx
      nixosModules.services.rustdesk
    ];
  nix.gc.options = lib.mkForce "-d";
}
