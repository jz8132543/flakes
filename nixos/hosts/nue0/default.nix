{ nixosModules, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.services.opencloud.all
    # ++ nixosModules.services.mail.all ++ [
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      # nixosModules.services.headscale
      # nixosModules.services.derp
      # nixosModules.services.stun
      nixosModules.services.postgres
      nixosModules.services.minio
      nixosModules.services.doraim
      nixosModules.services.ntfy
      (import nixosModules.services.atuin { })
      nixosModules.services.vscode
      # nixosModules.services.ollama
      nixosModules.services.proxy
      nixosModules.services.jellyfin
      nixosModules.services.syncthing
      nixosModules.services.reader
      # nixosModules.services.searx
      nixosModules.services.plex
      # nixosModules.services.authentik
      # (import nixosModules.services.ebook-sender { })
      # (import nixosModules.services.kindle-sender { })
      (import nixosModules.services.keycloak { PG = "127.0.0.1"; })
      nixosModules.services.headscale
      (import nixosModules.services.vaultwarden { PG = "127.0.0.1"; })
      (import nixosModules.services.alist { PG = "127.0.0.1"; })
      # (import nixosModules.services.office { })
      # (import nixosModules.services.nextcloud { })
      (import nixosModules.services.mastodon { PG = "127.0.0.1"; })
      (import nixosModules.services.matrix { PG = "127.0.0.1"; })
      # TODO
      # nixosModules.services.pastebin
    ];
}
