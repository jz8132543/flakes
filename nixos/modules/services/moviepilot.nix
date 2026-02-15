{
  bigMemoryMode ? false,
}:
{
  config,
  lib,
  ...
}:
let

  # Configuration
  domain = "tv.${config.networking.domain}";
  webPort = config.ports.moviepilot or 3000;
  configPath = "/data/.state/moviepilot";
  mediaPath = "/data/media";
  downloadPath = "/data/downloads";

  moviepilotImage = "jxxghp/moviepilot:latest";

  # Environment variables for MoviePilot
  moviepilotEnv = {
    TZ = "Asia/Shanghai";
    PUID = "0";
    PGID = "0";
    UMASK = "022";
    WORKDIR = "/moviepilot";
    CONFIG_DIR = "/config";

    # Web UI
    NGINX_PORT = toString webPort;
    PORT = toString webPort;

    # Database (SQLite is used by default when DB_HOST is empty)

    # Big Memory Mode
    BIG_MEMORY_MODE = if bigMemoryMode then "true" else "false";

    # Download clients
    DOWNLOADER = "qbittorrent";
    QB_HOST = "127.0.0.1:8080";
    QB_USER = "admin";

    # Media server
    MEDIASERVER = "jellyfin";
    JELLYFIN_HOST = "http://127.0.0.1:8096";

    # Plugin repos
    PLUGIN_MARKET = "https://github.com/jxxghp/MoviePilot-Plugins,https://github.com/thsrite/MoviePilot-Plugins";
  };
in
{
  # ═══════════════════════════════════════════════════════════════
  # OCI Container - MoviePilot
  # ═══════════════════════════════════════════════════════════════
  virtualisation.oci-containers = {
    containers.moviepilot = {
      image = moviepilotImage;
      autoStart = true;

      volumes = [
        "${configPath}:/config"
        "${configPath}/core:/moviepilot/.cache/ms-playwright"
        "${mediaPath}:/media"
        "${downloadPath}:/downloads"
        # qBittorrent torrent files for cross-seed (optional, created by tmpfiles)
        "/var/lib/qBittorrent/qBittorrent/BT_backup:/BT_backup:ro"
        # Podman socket for container management
        "/run/podman/podman.sock:/var/run/docker.sock:ro"
        # Mount host plugin directory for persistence
        "/srv/moviepilot-plugins:/app/plugins"
      ];

      environment = moviepilotEnv;

      # Secrets passed via environment file
      environmentFiles = [
        config.sops.templates."moviepilot-env".path
      ];

      extraOptions = [
        "--network=host"
        "--hostname=moviepilot"
      ];
    };
  };

  # ═══════════════════════════════════════════════════════════════
  # Sops Template for Secrets
  # ═══════════════════════════════════════════════════════════════
  sops.templates."moviepilot-env" = {
    content =
      let
        inherit (config.sops) placeholder;
      in
      ''
        SUPERUSER_PASSWORD=${placeholder."password"}
        API_TOKEN=${placeholder."media/moviepilot_api_key"}
        QB_PASSWORD=${placeholder."password"}
        JELLYFIN_API_KEY=${placeholder."media/jellyfin_api_key"}
        JELLYFIN_PASSWORD=${placeholder."password"}
        #GITHUB_TOKEN=${placeholder."nix/github-token"}
      '';
    owner = "root";
  };

  # ═══════════════════════════════════════════════════════════════
  # Data Directories
  # ═══════════════════════════════════════════════════════════════
  systemd.tmpfiles.settings."moviepilot" = {
    "${configPath}".d = {
      mode = "0755";
    };
    "${configPath}/core".d = {
      mode = "0755";
    };
    "${mediaPath}".d = {
      mode = "0755";
    };
    "${mediaPath}/movies".d = {
      mode = "0755";
    };
    "${mediaPath}/tv".d = {
      mode = "0755";
    };
    "${mediaPath}/anime".d = {
      mode = "0755";
    };
    "${downloadPath}".d = {
      mode = "0755";
    };
    "${downloadPath}/torrents".d = {
      mode = "0755";
    };
    # qBittorrent BT_backup for cross-seed
    "/var/lib/qBittorrent/qBittorrent/BT_backup".d = {
      mode = "0755";
    };
  };

  # ═══════════════════════════════════════════════════════════════
  # Traefik Routes (for external access, MoviePilot + qBittorrent)
  # ═══════════════════════════════════════════════════════════════
  services.traefik.proxies = {
    moviepilot = {
      rule = "Host(`${domain}`)";
      target = "http://127.0.0.1:${toString webPort}";
    };
    # Access via FQDN path: {fqdn}/moviepilot
    moviepilot-fqdn = {
      rule = "Host(`${config.networking.fqdn}`) && PathPrefix(`/moviepilot`)";
      target = "http://127.0.0.1:${toString webPort}";
      middlewares = [ "moviepilot-stripprefix" ];
    };
    # qBittorrent: tv. and FQDN /qbit
    qbittorrent-tv = {
      rule = "Host(`tv.${config.networking.domain}`) && PathPrefix(`/qbit`)";
      target = "http://localhost:8080";
      middlewares = [ "qbittorrent-stripprefix" ];
    };
    qbittorrent-fqdn = {
      rule = "Host(`${config.networking.fqdn}`) && PathPrefix(`/qbit`)";
      target = "http://localhost:8080";
      middlewares = [ "qbittorrent-stripprefix" ];
    };
  };

  services.traefik.dynamic.files.nixos.settings.http.middlewares = {
    moviepilot-stripprefix.stripPrefix.prefixes = [ "/moviepilot" ];
    qbittorrent-stripprefix.stripPrefix.prefixes = [ "/qbit" ];
  };
  # ═══════════════════════════════════════════════════════════════
  # qBittorrent Service (merged)
  # ═══════════════════════════════════════════════════════════════
  services.qbittorrent = {
    enable = true;
    user = "qbittorrent";
    group = "media";
    profileDir = "/var/lib/qbittorrent";
    webuiPort = 8080;
    openFirewall = true;
  };

  # Disable DynamicUser for stable permissions
  systemd.services.qbittorrent.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "qbittorrent";
    Group = lib.mkForce "media";
  };

  users = {
    users.qbittorrent = {
      home = "/var/lib/qbittorrent";
      group = "media";
      isSystemUser = true;
      extraGroups = [ "media" ];
    };
  };

  # Torrent directories
  systemd.tmpfiles.settings.srv-torrents = {
    "/srv/torrents".d = {
      user = "qbittorrent";
      group = "media";
      mode = "0775";
    };
    "/srv/torrents/downloading".d = {
      user = "qbittorrent";
      group = "media";
      mode = "0775";
    };
    "/srv/torrents/completed".d = {
      user = "qbittorrent";
      group = "media";
      mode = "0775";
    };
  };

  # ═══════════════════════════════════════════════════════════════
  # Persistence
  # ═══════════════════════════════════════════════════════════════
  environment.global-persistence.directories = [
    configPath
    "/data" # Media and downloads
  ];

  # ═══════════════════════════════════════════════════════════════
  # Auto-Configured Features (开箱即用)
  # ═══════════════════════════════════════════════════════════════
  # ✅ PostgreSQL 数据库连接 (需手动在 PG 服务器创建数据库)
  # ✅ Redis 缓存 (本地自动配置)
  # ✅ qBittorrent 下载器连接 (http://127.0.0.1:8080)
  # ✅ Jellyfin 媒体服务器连接 (http://127.0.0.1:8096)
  # ✅ M-Team 站点 API 认证
  # ✅ PTTime 站点 API 认证
  # ✅ 下载路径和媒体库路径配置
  # ✅ 硬链接转移模式 (同文件系统)
  # ✅ 插件市场 (官方 + thsrite)
  #
  # ═══════════════════════════════════════════════════════════════
  # 仅需手动配置：CookieCloud 浏览器扩展
  # ═══════════════════════════════════════════════════════════════
  # MoviePilot 内置了 CookieCloud 服务器，配置浏览器扩展：
  #   - 服务器地址: https://tv.<domain>/cookiecloud
  #   - 用户KEY: 在 MoviePilot 设置 -> CookieCloud 中生成
  #   - 端对端加密密码: 自定义密码
  #
  # Chrome 扩展: https://chrome.google.com/webstore/detail/cookiecloud
  # Firefox 扩展: https://addons.mozilla.org/firefox/addon/cookiecloud
  #
  ## ...comments removed...
}
