{ nixosModules, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    # ++ nixosModules.services.opencloud.all
    # ++ nixosModules.services.mail.all
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

      # Media Stack (Based on Misterio77/nix-config)
      ../../modules/services/media/default.nix

      nixosModules.services.syncthing
      nixosModules.services.reader
      nixosModules.services.proxy
      # nixosModules.services.searx
      # nixosModules.services.plex # Replaced by Jellyfin/Infuse stack
      # nixosModules.services.authentik
      # (import nixosModules.services.ebook-sender { })
      # (import nixosModules.services.kindle-sender { })
      (import nixosModules.services.keycloak { PG = "127.0.0.1"; })
      nixosModules.services.headscale
      (import nixosModules.services.vaultwarden { PG = "127.0.0.1"; })
      (import nixosModules.services.alist { PG = "127.0.0.1"; })
      # (import nixosModules.services.office { })
      # (import nixosModules.services.nextcloud { })
      (import nixosModules.services.mastodon { })
      (import nixosModules.services.matrix { })
      # TODO
      # nixosModules.services.pastebin

      # 📊 监控服务 (alertmanager 已合并到 prometheus, postgres-exporter 已合并到 postgres)
      nixosModules.services.telegraf
      nixosModules.services.prometheus
      nixosModules.services.grafana.default
    ];

  # Media group for shared file access
  users.groups.media = { };
}
