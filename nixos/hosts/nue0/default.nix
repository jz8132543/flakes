{ nixosModules, inputs, ... }:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.services.media.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.services.traefik
      nixosModules.services.fakehttp
      nixosModules.services.dev
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
  environment.networkTune = {
    enable = true;
    bandwidth = 2500; # Mbps 单向
    realBandwidth = 2500;
    rtt = 180; # ms，国际线路
    ram = 4096; # MB，可用内存
    cpus = 4; # vCPU 数
    highLoss = true; # 高丢包国际线路
  };
  services.fakehttp = {
    enable = true;
    # 自动利用内置的 domainPool 域名池（包括 jsinfo 等测速和视频域名）
    # 在服务启动时生成真实 HTTP 和 TLS ClientHello 进行并发混淆
    # cu 作为客户端主动发起的出站 TCP 流量会被混淆（如 iperf3 -c 从 cu 发起）
    # 注：若要解除用户到 cu 的反向上传限速，需在用户侧路由器运行 FakeHTTP
  };
}
