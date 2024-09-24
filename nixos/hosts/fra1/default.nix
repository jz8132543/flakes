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
      nixosModules.services.postgres
      nixosModules.services.doraim
      nixosModules.services.ntfy
      nixosModules.services.sogo
      nixosModules.services.pastebin
      nixosModules.services.ollama
      (import nixosModules.services.matrix { })
      (import nixosModules.services.keycloak { })
      (import nixosModules.services.vaultwarden { })
      (import nixosModules.services.alist { })
    ];
}
