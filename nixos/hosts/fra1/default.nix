{nixosModules, ...}: {
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      nixosModules.services.derp
      nixosModules.services.postgres
      nixosModules.services.doraim
      nixosModules.services.vaultwarden
      nixosModules.services.matrix
      nixosModules.services.keycloak
      nixosModules.services.prometheus
      nixosModules.services.mastodon
      # nixosModules.services.seafile
      nixosModules.services.searx
    ];
}
