{ nixosModules, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.services.mail.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      nixosModules.services.headscale
      nixosModules.services.derp
      nixosModules.services.hydra
      nixosModules.services.sogo
      nixosModules.services.postgres
      nixosModules.services.doraim
      nixosModules.services.vaultwarden
      # nixosModules.services.matrix
      nixosModules.services.keycloak
      nixosModules.services.prometheus
      nixosModules.services.mastodon
      # nixosModules.services.seafile
      nixosModules.services.searx
    ];
}
