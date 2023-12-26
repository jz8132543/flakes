{nixosModules, ...}: {
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      nixosModules.services.headscale
      nixosModules.services.derp
      nixosModules.services.proxy
      nixosModules.services.tuic
      nixosModules.services.keycloak
      nixosModules.services.postgres
      nixosModules.services.doraim
      nixosModules.services.vaultwarden
    ];
}
