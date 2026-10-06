{
  inputs,
  config,
  lib,
  nixosModules,
  pkgs,
  ...
}:
let
  cfg = config.services.degoog;
  valkeyPort = 16380;

  dbName = "degoog";
  dbUser = "degoog";

  flareSolverrPort = config.ports.flaresolverr;
in
{
  imports = [
    inputs.degoog.nixosModules.default
    nixosModules.services.traefik
    nixosModules.services.media.flaresolverr
  ];

  options.services.degoog = {
    domain = lib.mkOption {
      type = lib.types.str;
      default = "s.${config.networking.domain}";
      description = "Public domain for Degoog.";
    };

    flaresolverr.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Connect Degoog to FlareSolverr for Cloudflare bypass.";
    };

    ketch.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install Ketch CLI for web scraping / RAG extraction.";
    };

    mcp.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Degoog MCP gateway for AI agent integration.";
    };

    valkey.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable dedicated Redis cache for Degoog (backed by valkey).";
    };

    autoInstallOfficialExtensions = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically clone and install official plugins, transports (including 4play), themes, engines, and autocomplete providers.";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── SOPS ──────────────────────────────────────────────────────────────
    sops.secrets."password" = { };

    sops.templates."degoog-env" = {
      content = ''
        DEGOOG_SETTINGS_PASSWORDS=${config.sops.placeholder."password"}
      '';
    };

    # ── Valkey（Redis-compatible 高速缓存）────────────────────────────────
    # 数据库和用户已由 `sudo -u postgres psql` 手动创建（幂等脚本）
    services.redis.servers.degoog = lib.mkIf cfg.valkey.enable {
      enable = true;
      port = valkeyPort;
      bind = "127.0.0.1";
    };

    systemd.services.redis-degoog = lib.mkIf cfg.valkey.enable {
      serviceConfig.ExecStart = lib.mkForce "${pkgs.valkey}/bin/valkey-server /var/lib/redis-degoog/redis.conf";
    };

    # ── Degoog 核心配置 ────────────────────────────────────────────────────
    services.degoog = {
      # DB 由手动 psql 建好，不使用 configurePostgres
      environmentFile = config.sops.templates."degoog-env".path;

      environment = {
        # HTTP 端口监听，Traefik 反向代理
        DEGOOG_PORT = config.ports.degoog;
        DEGOOG_UNIX_SOCKET = null;

        # 信任 Traefik 反向代理的 X-Forwarded-For 真实客户端 IP
        DEGOOG_DISTRUST_PROXY = false;

        # PostgreSQL via Unix socket peer auth（trust，无密码）
        DEGOOG_POSTGRES_HOST = "/var/run/postgresql";
        DEGOOG_POSTGRES_USER = dbUser;
        DEGOOG_POSTGRES_DATABASE = dbName;

        # Valkey 缓存
        DEGOOG_VALKEY_URL = lib.mkIf cfg.valkey.enable "redis://127.0.0.1:${toString valkeyPort}";

        # 允许外部扩展解析 degoog 的 node_modules 依赖 (如 cheerio 等)
        NODE_PATH = "${config.services.degoog.package}/share/degoog/node_modules";

        # FlareSolverr（穿透 Cloudflare / JS Challenge）
        DEGOOG_FLARESOLVERR_URL = lib.mkIf cfg.flaresolverr.enable "http://127.0.0.1:${toString flareSolverrPort}";

        # MCP 端点 /mcp（Claude Desktop、Cursor、AI Agent 调用）
        DEGOOG_MCP_ENABLED = lib.mkIf cfg.mcp.enable true;

        # Beta 商店：Transports (4play)、Slot Plugins、Bang Commands、扩展引擎
        DEGOOG_BETA_STORE = "1";

        DEGOOG_WIZARD = false;
        DEGOOG_PUBLIC_INSTANCE = false;
        DEGOOG_LANGUAGE = "zh-CN";
        TZ = config.time.timeZone or "Asia/Shanghai";
      };
    };

    # ── 服务依赖与扩展自动装配 ───────────────────────────────────────────────
    systemd.services.degoog = lib.mkMerge [
      {
        after = [ "postgresql.service" ];
        wants = [ "postgresql.service" ];
        path = [
          pkgs.git
          pkgs.coreutils
          pkgs.jq
          pkgs.curl
          pkgs.curl-impersonate
        ];
        preStart = lib.mkIf cfg.autoInstallOfficialExtensions ''
                    mkdir -p /var/lib/degoog/plugins /var/lib/degoog/transports /var/lib/degoog/themes /var/lib/degoog/engines /var/lib/degoog/autocomplete /var/lib/degoog/shortcuts /var/lib/degoog/store
                    ln -sfn "${config.services.degoog.package}/share/degoog/node_modules" /var/lib/degoog/node_modules

                    STORE_DIR="/var/lib/degoog/store/degoog-org-official-extensions"
                    if [ ! -d "$STORE_DIR/.git" ]; then
                      git clone --depth 1 https://github.com/degoog-org/official-extensions.git "$STORE_DIR" || true
                    else
                      (cd "$STORE_DIR" && git pull --ff-only) || true
                    fi

                    copy_ext() {
                      src_dir="$1"
                      dst_dir="$2"
                      [ -d "$src_dir" ] || return 0
                      mkdir -p "$dst_dir"
                      for item in "$src_dir"/*; do
                        [ -e "$item" ] || continue
                        name=$(basename "$item")
                        # 排除需要单独独立安装依赖的第三方传输层
                        [ "$name" = "cloakbrowser" ] && continue
                        if [ ! -e "$dst_dir/$name" ] && [ ! -e "$dst_dir/degoog-org-official-extensions-$name" ] && [ ! -e "$dst_dir/degoog-org-official-extensions-$name-theme" ] && [ ! -e "$dst_dir/degoog-org-official-extensions-$name-autocomplete" ]; then
                          cp -r "$item" "$dst_dir/"
                        fi
                      done
                    }

                    if [ -d "$STORE_DIR" ]; then
                      copy_ext "$STORE_DIR/plugins" /var/lib/degoog/plugins
                      copy_ext "$STORE_DIR/transports" /var/lib/degoog/transports
                      copy_ext "$STORE_DIR/themes" /var/lib/degoog/themes
                      copy_ext "$STORE_DIR/engines" /var/lib/degoog/engines
                      copy_ext "$STORE_DIR/autocomplete" /var/lib/degoog/autocomplete
                      copy_ext "$STORE_DIR/shortcuts" /var/lib/degoog/shortcuts
                    fi

                    # 清理无法独立运行的 cloakbrowser 与已迁移的原名重复目录
                    rm -rf /var/lib/degoog/transports/*cloakbrowser* /var/lib/degoog/transports/degoog-fplay-DEPRECATED
                    for kind in plugins transports themes engines autocomplete; do
                      [ -d "/var/lib/degoog/$kind" ] || continue
                      for item in /var/lib/degoog/"$kind"/*; do
                        [ -e "$item" ] || continue
                        base=$(basename "$item")
                        case "$base" in
                          degoog-org-official-extensions-*) ;;
                          *)
                            if [ -e "/var/lib/degoog/$kind/degoog-org-official-extensions-$base" ] || [ -e "/var/lib/degoog/$kind/degoog-org-official-extensions-$base-theme" ] || [ -e "/var/lib/degoog/$kind/degoog-org-official-extensions-$base-autocomplete" ]; then
                              rm -rf "$item"
                            fi
                            ;;
                        esac
                      done
                    done

                    # 同步 repos.json 状态，让官方商店 UI 正确识别全部扩展为已安装 (Installed)
                    REPOS_FILE="/var/lib/degoog/repos.json"
                    PKG_FILE="$STORE_DIR/package.json"
                    if [ -f "$PKG_FILE" ]; then
                      [ -f "$REPOS_FILE" ] || echo '{"repos":[],"installed":[]}' > "$REPOS_FILE"
                      INSTALLED_JSON=$(jq -c '
                        [
                          (.plugins // [] | .[] | {repoUrl: "https://github.com/degoog-org/official-extensions.git", type: "plugin", itemPath: .path, installedAs: ("degoog-org-official-extensions-" + (.path | split("/")[-1])), version: (.version // "0.0.0"), installedAt: "2026-09-29T00:00:00.000Z"}),
                          (.transports // [] | .[] | select(.path != "transports/cloakbrowser") | {repoUrl: "https://github.com/degoog-org/official-extensions.git", type: "transport", itemPath: .path, installedAs: ("degoog-org-official-extensions-" + (.path | split("/")[-1])), version: (.version // "0.0.0"), installedAt: "2026-09-29T00:00:00.000Z"}),
                          (.themes // [] | .[] | {repoUrl: "https://github.com/degoog-org/official-extensions.git", type: "theme", itemPath: .path, installedAs: ("degoog-org-official-extensions-" + (.path | split("/")[-1]) + "-theme"), version: (.version // "0.0.0"), installedAt: "2026-09-29T00:00:00.000Z"}),
                          (.engines // [] | .[] | {repoUrl: "https://github.com/degoog-org/official-extensions.git", type: "engine", itemPath: .path, installedAs: ("degoog-org-official-extensions-" + (.path | split("/")[-1])), version: (.version // "0.0.0"), installedAt: "2026-09-29T00:00:00.000Z"}),
                          (.autocomplete // [] | .[] | {repoUrl: "https://github.com/degoog-org/official-extensions.git", type: "autocomplete", itemPath: .path, installedAs: ("degoog-org-official-extensions-" + (.path | split("/")[-1]) + "-autocomplete"), version: (.version // "0.0.0"), installedAt: "2026-09-29T00:00:00.000Z"}),
                          (.shortcuts // [] | .[] | {repoUrl: "https://github.com/degoog-org/official-extensions.git", type: "shortcut", itemPath: .path, installedAs: ("degoog-org-official-extensions-" + (.path | split("/")[-1]) + "-shortcut"), version: (.version // "0.0.0"), installedAt: "2026-09-29T00:00:00.000Z"})
                        ]
                      ' "$PKG_FILE")

                      jq --argjson inst "$INSTALLED_JSON" '
                        .repos = [
                          {
                            url: "https://github.com/degoog-org/official-extensions.git",
                            localPath: "degoog-org-official-extensions",
                            name: "official-extensions",
                            description: "Plugins, themes, engines, and transports for degoog search.",
                            error: null,
                            repoImage: "https://avatars.githubusercontent.com/u/280656364"
                          }
                        ] | .installed = $inst
                      ' "$REPOS_FILE" > "$REPOS_FILE.tmp" && mv "$REPOS_FILE.tmp" "$REPOS_FILE"
                    fi

                    # 自动配置主流搜索引擎默认启用 (Google, Bing, Brave, DuckDuckGo)
                    DEFAULT_ENGINES="/var/lib/degoog/default-engines.json"
                    if [ ! -f "$DEFAULT_ENGINES" ]; then
                      cat > "$DEFAULT_ENGINES" << 'EOF'
          {
            "degoog-org-official-extensions-google": true,
            "degoog-org-official-extensions-bing": true,
            "degoog-org-official-extensions-brave": true,
            "degoog-org-official-extensions-duckduckgo": true,
            "google": true,
            "bing": true,
            "brave": true,
            "duckduckgo": true
          }
          EOF
                    fi

                    # 自动配置流式渐进加载 (Enable streaming results experimental)
                    SERVER_SETTINGS="/var/lib/degoog/server-settings.json"
                    if [ -f "$SERVER_SETTINGS" ]; then
                      jq '.settings.streamingEnabled = "true" | .settings.streamingAutoRetry = "true" | .settings.streamingMaxRetries = "2"' "$SERVER_SETTINGS" > "$SERVER_SETTINGS.tmp" && mv "$SERVER_SETTINGS.tmp" "$SERVER_SETTINGS" || true
                    else
                      cat > "$SERVER_SETTINGS" << 'EOF'
          {
            "wizard": false,
            "settings": {
              "streamingEnabled": "true",
              "streamingAutoRetry": "true",
              "streamingMaxRetries": "2"
            }
          }
          EOF
                    fi
        '';
      }
      (lib.mkIf cfg.valkey.enable {
        after = [ "redis-degoog.service" ];
        requires = [ "redis-degoog.service" ];
      })
      (lib.mkIf cfg.flaresolverr.enable {
        after = [ "flaresolverr.service" ];
        wants = [ "flaresolverr.service" ];
      })
    ];

    # ── Ketch CLI & Valkey tools ──────────────────────────────────────────
    environment.systemPackages =
      (lib.optional cfg.ketch.enable pkgs.ketch) ++ (lib.optional cfg.valkey.enable pkgs.valkey);

    # ── Traefik（仅保留 search 域名）────────────────────────────────────────
    services.traefik.proxies.degoog = {
      rule = "Host(`${cfg.domain}`)";
      target = "http://127.0.0.1:${toString config.ports.degoog}";
    };
  };
}
