{ nixosModules, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      # nixosModules.services.headscale
      nixosModules.services.derp
      nixosModules.services.proxy
      # nixosModules.services.postgres
      # nixosModules.services.doraim
      # nixosModules.services.ntfy
      # (import nixosModules.services.keycloak { })
      # (import nixosModules.services.vaultwarden { })
      # (import nixosModules.services.alist { })
    ];

  networking.hosts."100.64.0.4" = [
    "cu.dora.im"
    "cuv6.dora.im"
  ];
}
