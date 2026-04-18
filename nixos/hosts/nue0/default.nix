{ nixosModules, inputs, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.services.media.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      nixosModules.optimize.nix-cache-upload
      (import nixosModules.services.hydra { PG = "127.0.0.1"; })
      nixosModules.optimize.fakehttp
      nixosModules.optimize.dev
      nixosModules.services.doraim
      ../../modules/services/matrix-rtc.nix
      {
        services.matrix-rtc.enable = true;
      }
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
      nixosModules.services.sub
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
      # ../../modules/services/mas.nix
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

  services.openclaw.enable = false;
  services.ai.litellm.enable = true;
  services.easytierMesh.role = "bootstrap";

  environment.seedbox = {
    enable = true;
    proxyHost = "shg0.mag";
    # proxyPort = 10080;
  };
  environment.networkTune = {
    bandwidth = 2500; # Mbps 单向
    realBandwidth = 2500;
    rtt = 180; # ms，国际线路
    ram = 4096; # MB，可用内存
  };

  services.subscriptionPublisher = {
    enable = true;
    nodes = [
      {
        name = "nue0";
        server = "nue0.dora.im";
        port = 443;
        regions = [ "US" ];
      }
      {
        name = "nue0-kxy";
        server = "cu.dora.im";
        port = 50561;
        regions = [ "EU" ];
      }
      {
        name = "hkg4";
        server = "hkg4.dora.im";
        port = 443;
        regions = [ "HK" ];
      }
      {
        name = "hkg4-kxy";
        server = "cu.dora.im";
        port = 50562;
        regions = [ "HK" ];
      }
      {
        name = "hkg5";
        server = "hkg5.dora.im";
        port = 8555;
        regions = [ "HK" ];
      }
      {
        name = "tyo0";
        server = "tyo0.dora.im";
        port = 443;
        regions = [ "JP" ];
      }
      {
        name = "tyo1";
        server = "tyo1.dora.im";
        port = 8555;
        regions = [ "JP" ];
      }
      {
        name = "sjc0";
        server = "sjc0.dora.im";
        port = 443;
        regions = [ "US" ];
      }
      {
        name = "can0-hkg5";
        server = "can0.dora.im";
        port = 8555;
        regions = [ "HK" ];
      }
      {
        name = "can1-hkg5";
        server = "can1.dora.im";
        port = 443;
        regions = [ "US" ];
      }
    ];
  };
}
