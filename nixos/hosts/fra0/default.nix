{ nixosModules, ... }: {
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.services.media.all
    ++ nixosModules.matrix.all
    ++ nixosModules.services.networking.dn42.all
    ++ nixosModules.services.atc.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      (import nixosModules.services.hydra { PG = "127.0.0.1"; })
      # nixosModules.optimize.fakehttp
      nixosModules.optimize.dev
      nixosModules.optimize.anti-balloon
      nixosModules.services.headscale
      # nixosModules.services.derp
      nixosModules.services.postgres
      # nixosModules.services.minio
      nixosModules.services.ntfy
      nixosModules.services.degoog
      (import nixosModules.services.atuin { })
      nixosModules.services.vscode
      # nixosModules.services.ollama
      nixosModules.services.syncthing
      nixosModules.services.lobechat
      nixosModules.services.obsidian-livesync
      nixosModules.services.zotero-sync-server
      nixosModules.services.reader
      (import nixosModules.services.xray {
      })
      nixosModules.services.sub
      nixosModules.services.cookiecloud
      nixosModules.services.moviepilot
      nixosModules.services.homepage
      nixosModules.services.home-assistant
      nixosModules.services.new-api
      nixosModules.services.cpa
      nixosModules.services.memos
      # nixosModules.services.plex # Replaced by Jellyfin/Infuse stack
      # nixosModules.services.authentik
      # (import nixosModules.services.ebook-sender { })
      # (import nixosModules.services.kindle-sender { })
      (import nixosModules.services.keycloak { PG = "127.0.0.1"; })
      # nixosModules.services.grimmory
      # ../../modules/services/mas.nix
      (import nixosModules.services.vaultwarden { PG = "127.0.0.1"; })
      (import nixosModules.services.alist { PG = "127.0.0.1"; })
      # (import nixosModules.services.office { }) # 已由 nextcloud.nix 导入
      (import nixosModules.nextcloud.core { PG = "127.0.0.1"; })
      nixosModules.nextcloud.talk-central
      # Coturn TURN 服务器由 nixosModules.matrix.all 中的 stun.nix 配置，Talk 复用它
      (import nixosModules.services.mastodon { PG = "127.0.0.1"; })
      nixosModules.services.pastebin
      nixosModules.services.linkwarden
      # nixosModules.services.easytier-web
      nixosModules.services.save-restricted-content-bot

      nixosModules.services.tailscale-proxy-pool

      # 📊 监控服务 (alertmanager 已合并到 prometheus, postgres-exporter 已合并到 postgres)
      nixosModules.services.telegraf
      nixosModules.services.prometheus
      nixosModules.services.grafana.default
      nixosModules.services.homepage
      nixosModules.services.homepage-machine
      nixosModules.services.adguard-mosdns
    ];

  services.moviepilot.enable = true;
  # services.ai.litellm.enable = true;
  services.new-api = {
    enable = true;
    oidc = {
      enable = true; # 后续在 Keycloak 创建 Client 并添加 sops 密钥 (new-api/oidc_client_secret) 后取消注释即可
    };
  };
  services.cpa.enable = true;
  services.degoog.enable = true;
  services.easytierMesh.role = "bootstrap";
  services.easytierMesh.web.enable = true;
  services.obsidianLiveSync.enable = true;

  # ── 分布式 Nextcloud Talk HPB 中心控制面 ─────────────────────
  services.nextcloud-talk-central = {
    enable = true;
    natsListen = "0.0.0.0";
    # talk.dora.im（中心节点）没有 Janus MCU，若注册为 Talk 信令服务器，
    # 客户端连上去后无法发起视频通话。禁用后清理脚本会自动从 Nextcloud 中删除它，
    # 用户将被路由到边缘节点（sjc0 或 cu）。
    enableLocalSignaling = false;
  };

  services.tailscale-proxy-pool = {
    enable = true;
    exitNodes = [
      "surface.ts"
      "arx8.ts"
      "shg0.ts"
      # "op13.ts"
    ];

    poolPort = 10080;
  };

  environment.seedbox = {
    enable = true;
    proxyHost = "127.0.0.1";
    proxyPort = 10080;
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
        name = "fra0";
        server = "fra0.dora.im";
        port = 8555;
        regions = [ "EU" ];
      }
      {
        name = "fra0-kxy";
        server = "cu.dora.im";
        port = 50561;
        regions = [ "EU" ];
      }
      {
        name = "tyo0";
        server = "tyo0.dora.im";
        port = 8555;
        regions = [ "JP" ];
      }
      {
        name = "tyo0-kxy";
        server = "cu.dora.im";
        port = 50563;
        regions = [ "JP" ];
      }
      {
        name = "tyo1";
        server = "tyo1.dora.im";
        port = 8555;
        regions = [ "JP" ];
      }
      {
        name = "tyo1-kxy";
        server = "cu.dora.im";
        port = 50565;
        regions = [ "JP" ];
      }
      {
        name = "sjc0";
        server = "sjc0.dora.im";
        port = 8555;
        regions = [ "US" ];
      }
      {
        name = "sjc0-kxy";
        server = "cu.dora.im";
        port = 50562;
        regions = [ "US" ];
      }
      # {
      #   name = "can0-hkg5";
      #   server = "can0.dora.im";
      #   port = 8555;
      #   regions = [ "HK" ];
      # }
      # {
      #   name = "can1-hkg5";
      #   server = "can1.dora.im";
      #   port = 443;
      #   regions = [ "HK" ];
      # }
      {
        name = "hkg0";
        server = "hkg0.dora.im";
        port = 8555;
        regions = [ "HK" ];
      }
      {
        name = "hkg0-kxy";
        server = "cu.dora.im";
        port = 50566;
        regions = [ "HK" ];
      }
      {
        name = "hkg5";
        server = "hkg5.dora.im";
        port = 8555;
        regions = [ "HK" ];
      }
      {
        name = "hkg5-kxy";
        server = "cu.dora.im";
        port = 50564;
        regions = [ "HK" ];
      }
    ];
  };

  # 仅为 fra0 配置 4GiB 独立 Swapfile（置于持久化 /var/lib 下，规避 rootfs 每次开机重置）
  # NixOS 的 swap 模块会自动检测 Btrfs 并调用 btrfs filesystem mkswapfile，自动禁用 CoW (chattr +C) 与压缩
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 4 * 1024;
    }
  ];
}
