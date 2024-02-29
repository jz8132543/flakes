{
  nixosModules,
  lib,
  ...
}: {
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.services.mail.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      nixosModules.services.derp
      nixosModules.services.proxy
      nixosModules.services.tuic
      nixosModules.services.searx
      nixosModules.services.rustdesk
      nixosModules.services.sogo
    ];
  nix.gc.options = lib.mkForce "-d";
}
