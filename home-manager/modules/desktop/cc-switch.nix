{
  config,
  pkgs,
  ...
}:
let
  hermesPkg = pkgs.writeShellScriptBin "hermes" ''
    exec ${pkgs.uv}/bin/uvx hermes-agent "$@"
  '';
in
{
  home.packages = with pkgs; [
    cc-switch
    claude-code
    uv
    hermesPkg
  ];

  # 用户登录桌面时开机自启 CC Switch (托盘运行)
  xdg.configFile."autostart/cc-switch.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=CC Switch
    Exec=${pkgs.cc-switch}/bin/cc-switch
    Icon=cc-switch
    Comment=Switch LLM Providers for AI Coding Assistants
    Terminal=false
    Categories=Utility;
    X-GNOME-Autostart-enabled=true
  '';

  # 持久化相关配置与工作目录
  home.global-persistence = {
    directories = [
      ".cc-switch"
      ".local/share/com.ccswitch.desktop"
      ".claude"
      ".config/claude"
      ".hermes"
      ".config/hermes"
    ];
    files = [
      ".claude.json"
    ];
  };

  sops.secrets."cc_switch/api_key" = { };

  systemd.user.services.cc-switch-init = {
    Unit = {
      Description = "Initialize CC Switch Config from SOPS";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = toString (
        pkgs.writeShellScript "cc-switch-init" ''
                  # Wait briefly to ensure SOPS secrets are mounted and available
                  sleep 1

                  if [ ! -f "${config.sops.secrets."cc_switch/api_key".path}" ]; then
                    echo "API key not found, skipping CC Switch init"
                    exit 0
                  fi

                  # 1. 确保目录存在并获取 API 密钥
                  mkdir -p ~/.cc-switch
                  API_KEY=$(cat "${config.sops.secrets."cc_switch/api_key".path}")
                  DB_PATH="$HOME/.cc-switch/cc-switch.db"
                  LOCALSTORAGE_PATH="$HOME/.local/share/com.ccswitch.desktop/localstorage/tauri_localhost_0.localstorage"

                  # 2. 动态拉取中转站可用模型，并注入 SQLite 数据库，同时清除官方默认 API
                  ${pkgs.python3}/bin/python3 - <<PYEOF
          import urllib.request
          import json
          import sqlite3
          import os

          api_key = "$API_KEY"
          base_url = "https://aigw.c5y.moe"
          api_base = f"{base_url}/v1"
          db_path = os.path.expanduser("~/.cc-switch/cc-switch.db")

          req = urllib.request.Request(
              f"{api_base}/models",
              headers={"Authorization": f"Bearer {api_key}", "User-Agent": "cc-switch/1.0"}
          )

          try:
              with urllib.request.urlopen(req, timeout=10) as resp:
                  data = json.loads(resp.read().decode())
                  models = [m["id"] for m in data.get("data", [])]
          except Exception as e:
              print("Fetch models error, fallback to defaults:", e)
              models = [
                  "gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.6-terra", "gpt-5.6-luna",
                  "claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5",
                  "deepseek-v4-pro", "deepseek-v4-flash",
                  "kimi-k3", "kimi-k2.7-code", "kimi-k2.6", "kimi-k2.5",
                  "qwen3.8-max", "qwen3.7-max", "qwen3.7-plus", "qwen3.6-max",
                  "grok-4.6", "grok-4.5", "minimax-m3", "minimax-m2.7",
                  "glm-5.2", "glm-5.1", "mimo-v2.5", "llama3.1-8B",
                  "gemini-3.5-flash", "gemini-3.6-flash", "gemini-3.1-pro-preview"
              ]

          con = sqlite3.connect(db_path)
          cur = con.cursor()

          # 创建表结构
          cur.execute("""
          CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT);
          """)
          cur.execute("""
          CREATE TABLE IF NOT EXISTS providers (
              id TEXT NOT NULL,
              app_type TEXT NOT NULL,
              name TEXT NOT NULL,
              settings_config TEXT NOT NULL,
              website_url TEXT,
              category TEXT,
              created_at INTEGER,
              sort_index INTEGER,
              notes TEXT,
              icon TEXT,
              icon_color TEXT,
              meta TEXT NOT NULL DEFAULT '{}',
              is_current BOOLEAN NOT NULL DEFAULT 0,
              in_failover_queue BOOLEAN NOT NULL DEFAULT 0,
              cost_multiplier TEXT NOT NULL DEFAULT '1.0',
              limit_daily_usd REAL,
              limit_monthly_usd REAL,
              provider_type TEXT,
              PRIMARY KEY (id, app_type)
          );
          """)

          # 1. 删掉默认官方 API 与占位符
          cur.execute("DELETE FROM providers WHERE id IN ('claude-official', 'claude-desktop-official', 'codex-official', 'gemini-official', 'default')")
          # 2. 清除之前生成的 c5y 提供者以便全量刷新
          cur.execute("DELETE FROM providers WHERE id LIKE 'c5y-%' OR id LIKE 'universal-%'")

          now_ms = 1787840479324

          # 3. 注册 NewAPI 通用中转站主设置
          universal_json = {
              "cc008692-b227-447a-a53d-63e4a68e5dcf": {
                  "id": "cc008692-b227-447a-a53d-63e4a68e5dcf",
                  "name": "玲碗",
                  "providerType": "newapi",
                  "apps": {"claude": True, "codex": True, "gemini": True},
                  "baseUrl": api_base,
                  "apiKey": api_key,
                  "models": {
                      "claude": {
                          "model": "claude-sonnet-5",
                          "haikuModel": "claude-haiku-4-5-20251001",
                          "sonnetModel": "claude-sonnet-5",
                          "opusModel": "claude-opus-4-8"
                      },
                      "codex": {"model": "gpt-5.5", "reasoningEffort": "high"},
                      "gemini": {"model": "gemini-3.5-flash"}
                  },
                  "websiteUrl": base_url,
                  "icon": "newapi",
                  "iconColor": "#00A67E",
                  "createdAt": now_ms
              }
          }
          cur.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('universal_providers', ?)", (json.dumps(universal_json),))

          # 4. 根据从接口获取到的所有模型，全量注入 Provider 配置
          for model in sorted(models):
              lower_m = model.lower()
              
              icon = "custom"
              icon_color = "#666666"
              if "deepseek" in lower_m:
                  icon, icon_color = "deepseek", "#4D6BFE"
              elif "qwen" in lower_m:
                  icon, icon_color = "qwen", "#615CED"
              elif "kimi" in lower_m or "moonshot" in lower_m:
                  icon, icon_color = "kimi", "#00D1A0"
              elif "grok" in lower_m:
                  icon, icon_color = "grok", "#000000"
              elif "minimax" in lower_m:
                  icon, icon_color = "minimax", "#FF5C00"
              elif "glm" in lower_m or "zhipu" in lower_m:
                  icon, icon_color = "zhipu", "#0C50FF"
              elif "llama" in lower_m:
                  icon, icon_color = "meta", "#0668E1"
              elif "mimo" in lower_m:
                  icon, icon_color = "custom", "#FF6700"
              elif "claude" in lower_m:
                  icon, icon_color = "claude", "#D97706"
              elif "gemini" in lower_m:
                  icon, icon_color = "gemini", "#4285F4"
              elif "gpt" in lower_m or "o1" in lower_m or "o3" in lower_m or "openai" in lower_m:
                  icon, icon_color = "openai", "#10A37F"
              
              # 1) Claude 模型
              if "claude" in lower_m:
                  is_curr = 1 if model == "claude-sonnet-5" else 0
                  cfg = json.dumps({
                      "env": {
                          "ANTHROPIC_BASE_URL": api_base,
                          "ANTHROPIC_AUTH_TOKEN": api_key,
                          "ANTHROPIC_MODEL": model,
                          "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5-20251001",
                          "ANTHROPIC_DEFAULT_SONNET_MODEL": model,
                          "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-4-8"
                      }
                  })
                  cur.execute("""
                      INSERT OR REPLACE INTO providers (id, app_type, name, settings_config, website_url, category, created_at, icon, icon_color, meta, is_current, in_failover_queue, cost_multiplier)
                      VALUES (?, 'claude', ?, ?, ?, 'aggregator', ?, ?, ?, '{}', ?, 0, '1.0')
                  """, (f"c5y-claude-{model}", f"玲碗 · {model}", cfg, base_url, now_ms, icon, icon_color, is_curr))
              
              # 2) Gemini 模型
              if "gemini" in lower_m:
                  is_curr = 1 if model == "gemini-3.5-flash" else 0
                  cfg = json.dumps({
                      "env": {
                          "GOOGLE_GEMINI_BASE_URL": api_base,
                          "GEMINI_API_KEY": api_key,
                          "GEMINI_MODEL": model
                      }
                  })
                  cur.execute("""
                      INSERT OR REPLACE INTO providers (id, app_type, name, settings_config, website_url, category, created_at, icon, icon_color, meta, is_current, in_failover_queue, cost_multiplier)
                      VALUES (?, 'gemini', ?, ?, ?, 'aggregator', ?, ?, ?, '{}', ?, 0, '1.0')
                  """, (f"c5y-gemini-{model}", f"玲碗 · {model}", cfg, base_url, now_ms, icon, icon_color, is_curr))
              
              # 3) 所有模型均注册到 Codex（OpenAI 协议）供 VS Code / Codex 使用
              is_curr_codex = 1 if model == "gpt-5.5" else 0
              toml_conf = f"""model_provider = "custom"
          model = "{model}"
          model_reasoning_effort = "high"
          disable_response_storage = true

          [model_providers.custom]
          name = "玲碗 ({model})"
          base_url = "{api_base}"
          wire_api = "responses"
          requires_openai_auth = true
          """
              cfg_codex = json.dumps({
                  "auth": {"OPENAI_API_KEY": api_key},
                  "config": toml_conf
              })
              cur.execute("""
                  INSERT OR REPLACE INTO providers (id, app_type, name, settings_config, website_url, category, created_at, icon, icon_color, meta, is_current, in_failover_queue, cost_multiplier)
                  VALUES (?, 'codex', ?, ?, ?, 'aggregator', ?, ?, ?, '{}', ?, 0, '1.0')
              """, (f"c5y-codex-{model}", f"玲碗 · {model}", cfg_codex, base_url, now_ms, icon, icon_color, is_curr_codex))

          con.commit()
          con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
          con.close()

          # 5. 配置静默启动（后台托盘运行，开机自启不弹前台主窗口）
          settings_path = os.path.expanduser("~/.cc-switch/settings.json")
          try:
              with open(settings_path, "r") as f:
                  cfg_data = json.load(f)
          except Exception:
              cfg_data = {}

          cfg_data["silentStartup"] = True
          cfg_data["showInTray"] = True
          cfg_data["minimizeToTrayOnClose"] = True
          cfg_data["launchOnStartup"] = True
          cfg_data["firstRunNoticeConfirmed"] = True

          with open(settings_path, "w") as f:
              json.dump(cfg_data, f, indent=2)
          PYEOF

                  # 3. 固化本地存储为中文界面
                  if [ -f "$LOCALSTORAGE_PATH" ]; then
                    ${pkgs.sqlite}/bin/sqlite3 "$LOCALSTORAGE_PATH" "INSERT OR REPLACE INTO ItemTable (key, value) VALUES ('language', x'7a006800');"
                  fi

                  echo "CC Switch configuration successfully synchronized with all remote models."
        ''
      );
    };
  };
}
