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
      nixosModules.services.postgres
      nixosModules.services.doraim
      (import nixosModules.services.keycloak {})
      (import nixosModules.services.vaultwarden {})
      (import nixosModules.services.alist {})
      # nixosModules.services.keycloak
      # nixosModules.services.vaultwarden
      # nixosModules.services.alist
    ];
}
