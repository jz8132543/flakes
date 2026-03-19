{ nixosModules, inputs, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.services.media.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      nixosModules.optimize.fakehttp
      nixosModules.optimize.dev
      nixosModules.services.doraim
      nixosModules.services.headscale
      # nixosModules.services.derp
      nixosModules.services.stun
      nixosModules.services.postgres
      nixosModules.services.minio
      nixosModules.services.doraim
      nixosModules.services.ntfy
      (import nixosModules.services.atuin { })
      nixosModules.services.vscode
      # nixosModules.services.ollama
      nixosModules.services.syncthing
      nixosModules.services.reader
      (import nixosModules.services.xray {
      })
      nixosModules.services.cookiecloud
      nixosModules.services.homepage
      nixosModules.services.searx
      nixosModules.services.openclaw.default
      nixosModules.services.litellm.default
      inputs.openclaw-nix.nixosModules.openclaw-gateway
      # nixosModules.services.plex # Replaced by Jellyfin/Infuse stack
      # nixosModules.services.authentik
      # (import nixosModules.services.ebook-sender { })
      # (import nixosModules.services.kindle-sender { })
      (import nixosModules.services.keycloak { PG = "127.0.0.1"; })
      (import nixosModules.services.vaultwarden { PG = "127.0.0.1"; })
      (import nixosModules.services.alist { PG = "127.0.0.1"; })
      # (import nixosModules.services.office { })
      # (import nixosModules.services.nextcloud { })
      (import nixosModules.services.mastodon { })
      (import nixosModules.services.matrix { })
      # TODO
      nixosModules.services.pastebin
      nixosModules.services.linkwarden

      # 📊 监控服务 (alertmanager 已合并到 prometheus, postgres-exporter 已合并到 postgres)
      nixosModules.services.telegraf
      nixosModules.services.prometheus
      nixosModules.services.grafana.default
      nixosModules.services.homepage
      nixosModules.services.homepage-machine
    ];

  services.openclaw.enable = true;
  services.ai.litellm.enable = true;

  environment.seedbox = {
    enable = true;
    proxyHost = "shg0.mag";
    # proxyPort = 10080;
  };
  environment.networkOmnitt = {
    bandwith = 2500; # Mbps 单向
    realbandwith = 2500;
    latencyMs = 180; # ms，国际线路
    memoryMB = 4096; # MB，可用内存
  };
}
