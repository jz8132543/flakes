{ nixosModules, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    # ++ nixosModules.services.mail.all ++ [
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      nixosModules.services.headscale
      # nixosModules.services.derp
      # nixosModules.services.stun
      nixosModules.services.postgres
      nixosModules.services.minio
      nixosModules.services.doraim
      nixosModules.services.ntfy
      # nixosModules.services.sogo
      nixosModules.services.pastebin
      # nixosModules.services.ollama
      nixosModules.services.proxy
      nixosModules.services.jellyfin
      nixosModules.services.syncthing
      nixosModules.services.reader
      (import nixosModules.services.ebook-sender { })
      (import nixosModules.services.kindle-sender { })
      # TEST
      nixosModules.services.mysql
      (import nixosModules.services.matrix { })
      (import nixosModules.services.keycloak { })
      (import nixosModules.services.vaultwarden { })
      (import nixosModules.services.alist { })
    ];
}
