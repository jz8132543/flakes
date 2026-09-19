{
  nixosModules,
  lib,
  ...
}:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    # ++ nixosModules.services.mail.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      nixosModules.services.derp
      nixosModules.services.proxy
      # nixosModules.services.tuic
      # nixosModules.services.searx
      # nixosModules.services.rustdesk
      # nixosModules.services.sogo
    ];
  nix.gc.options = lib.mkForce "-d";

  networking.hosts."100.64.0.4" = [
    "cu.dora.im"
    "cuv6.dora.im"
  ];
}
