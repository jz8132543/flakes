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

  sops.secrets = {
    "cc_switch/api_key" = { };
    "cpa/api_key" = { };
    "password" = { };
  };

  systemd.user.services.cc-switch-init = {
    Unit = {
      Description = "Initialize CC Switch Config from SOPS (C5Y + CPA)";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = toString (
        pkgs.writeShellScript "cc-switch-init" ''
                    sleep 1

                    mkdir -p ~/.cc-switch
                    DB_PATH="$HOME/.cc-switch/cc-switch.db"
                    LOCALSTORAGE_PATH="$HOME/.local/share/com.ccswitch.desktop/localstorage/tauri_localhost_0.localstorage"

                    API_KEY=""
                    if [ -f "${config.sops.secrets."cc_switch/api_key".path}" ]; then
                      API_KEY=$(cat "${config.sops.secrets."cc_switch/api_key".path}")
                    fi

                    CPA_API_KEY=""
                    if [ -f "${config.sops.secrets."cpa/api_key".path}" ]; then
                      CPA_API_KEY=$(cat "${config.sops.secrets."cpa/api_key".path}")
                    elif [ -f "${config.sops.secrets."password".path}" ]; then
                      CPA_API_KEY=$(cat "${config.sops.secrets."password".path}")
                    fi

                    export API_KEY
                    export CPA_API_KEY
                    export DOMAIN="${config.networking.domain or "dora.im"}"

                    ${pkgs.python3}/bin/python3 - <<'PYEOF'
                    import urllib.request
                    import json
                    import sqlite3
                    import os

                    api_key = os.environ.get("API_KEY", "")
                    cpa_api_key = os.environ.get("CPA_API_KEY", "")
                    domain = os.environ.get("DOMAIN", "dora.im")
                    db_path = os.path.expanduser("~/.cc-switch/cc-switch.db")

                    # 1. 获取 C5Y 玲碗模型列表
                    c5y_base = "https://aigw.c5y.moe/v1"
                    c5y_models = []
                    if api_key:
                        req = urllib.request.Request(
                            f"{c5y_base}/models",
                            headers={"Authorization": f"Bearer {api_key}", "User-Agent": "cc-switch/1.0"}
                        )
                        try:
                            with urllib.request.urlopen(req, timeout=10) as resp:
                                data = json.loads(resp.read().decode())
                                c5y_models = [m["id"] for m in data.get("data", [])]
                        except Exception as e:
                            print("Fetch c5y models error:", e)

                    if not c5y_models:
                        c5y_models = [
                            "gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "claude-sonnet-5", "claude-opus-5",
                            "deepseek-v4-pro", "kimi-k3", "gemini-3.5-flash"
                        ]

                    # 2. 获取自建 CPA 模型列表
                    cpa_base = f"https://cpa.{domain}/v1"
                    cpa_models = []
                    if cpa_api_key:
                        req_cpa = urllib.request.Request(
                            f"{cpa_base}/models",
                            headers={"Authorization": f"Bearer {cpa_api_key}", "User-Agent": "cc-switch/1.0"}
                        )
                        try:
                            with urllib.request.urlopen(req_cpa, timeout=10) as resp:
                                data_cpa = json.loads(resp.read().decode())
                                cpa_models = [m["id"] for m in data_cpa.get("data", [])]
                        except Exception as e:
                            print("Fetch CPA models error:", e)

                    if not cpa_models:
                        cpa_models = [
                            "claude-3-5-sonnet", "claude-opus-4-6-thinking", "gemini-3.8-flash",
                            "gemini-3.8-flash-high", "gpt-oss-120b", "kimi-k3"
                        ]

                    con = sqlite3.connect(db_path)
                    cur = con.cursor()

                    cur.execute("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT);")
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

                    # 清理默认与旧生成项
                    cur.execute("DELETE FROM providers WHERE id IN ('claude-official', 'claude-desktop-official', 'codex-official', 'gemini-official', 'default')")
                    cur.execute("DELETE FROM providers WHERE id LIKE 'c5y-%' OR id LIKE 'cpa-%'")

                    now_ms = 1787840479324

                    # 3. 注册 universal_providers：同时包含 玲碗 与 CPA
                    universal_json = {}
                    if api_key:
                        universal_json["c5y-universal"] = {
                            "id": "c5y-universal",
                            "name": "玲碗 (C5Y)",
                            "providerType": "newapi",
                            "apps": {"claude": True, "codex": True, "gemini": True, "opencode": True},
                            "baseUrl": c5y_base,
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
                            "websiteUrl": "https://aigw.c5y.moe",
                            "icon": "newapi",
                            "iconColor": "#00A67E",
                            "createdAt": now_ms
                        }

                    if cpa_api_key:
                        universal_json["cpa-universal"] = {
                            "id": "cpa-universal",
                            "name": "CPA (自建网关)",
                            "providerType": "newapi",
                            "apps": {"claude": True, "codex": True, "gemini": True, "opencode": True},
                            "baseUrl": cpa_base,
                            "apiKey": cpa_api_key,
                            "models": {
                                "claude": {
                                    "model": "claude-3-5-sonnet",
                                    "haikuModel": "claude-3-5-sonnet",
                                    "sonnetModel": "claude-3-5-sonnet",
                                    "opusModel": "claude-opus-4-6-thinking"
                                },
                                "codex": {"model": "gpt-oss-120b", "reasoningEffort": "medium"},
                                "gemini": {"model": "gemini-3.8-flash"}
                            },
                            "websiteUrl": f"https://cpa.{domain}",
                            "icon": "custom",
                            "iconColor": "#4285F4",
                            "createdAt": now_ms + 1000
                        }

                    cur.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('universal_providers', ?)", (json.dumps(universal_json),))

                    def insert_provider_models(prefix, provider_label, target_models, target_base, target_key, base_sort_index=0):
                        for idx, model in enumerate(sorted(target_models)):
                            sort_idx = base_sort_index + idx
                            lower_m = model.lower()
                            icon = "custom"
                            icon_color = "#666666"
                            if "deepseek" in lower_m: icon, icon_color = "deepseek", "#4D6BFE"
                            elif "qwen" in lower_m: icon, icon_color = "qwen", "#615CED"
                            elif "kimi" in lower_m: icon, icon_color = "kimi", "#00D1A0"
                            elif "grok" in lower_m: icon, icon_color = "grok", "#000000"
                            elif "minimax" in lower_m: icon, icon_color = "minimax", "#FF5C00"
                            elif "glm" in lower_m: icon, icon_color = "zhipu", "#0C50FF"
                            elif "llama" in lower_m: icon, icon_color = "meta", "#0668E1"
                            elif "claude" in lower_m: icon, icon_color = "claude", "#D97706"
                            elif "gemini" in lower_m: icon, icon_color = "gemini", "#4285F4"
                            elif "gpt" in lower_m or "o1" in lower_m or "o3" in lower_m: icon, icon_color = "openai", "#10A37F"

                            if "claude" in lower_m:
                                cfg = json.dumps({
                                    "env": {
                                        "ANTHROPIC_BASE_URL": target_base,
                                        "ANTHROPIC_AUTH_TOKEN": target_key,
                                        "ANTHROPIC_MODEL": model
                                    }
                                })
                                cur.execute("""
                                    INSERT OR REPLACE INTO providers (id, app_type, name, settings_config, website_url, category, created_at, sort_index, icon, icon_color, meta, is_current, in_failover_queue, cost_multiplier)
                                    VALUES (?, 'claude', ?, ?, ?, 'aggregator', ?, ?, ?, ?, '{}', 0, 0, '1.0')
                                """, (f"{prefix}-claude-{model}", f"{provider_label} · {model}", cfg, target_base, now_ms, sort_idx, icon, icon_color))

                            if "gemini" in lower_m:
                                cfg = json.dumps({
                                    "env": {
                                        "GOOGLE_GEMINI_BASE_URL": target_base,
                                        "GEMINI_API_KEY": target_key,
                                        "GEMINI_MODEL": model
                                    }
                                })
                                cur.execute("""
                                    INSERT OR REPLACE INTO providers (id, app_type, name, settings_config, website_url, category, created_at, sort_index, icon, icon_color, meta, is_current, in_failover_queue, cost_multiplier)
                                    VALUES (?, 'gemini', ?, ?, ?, 'aggregator', ?, ?, ?, ?, '{}', 0, 0, '1.0')
                                """, (f"{prefix}-gemini-{model}", f"{provider_label} · {model}", cfg, target_base, now_ms, sort_idx, icon, icon_color))

                            toml_conf = f"""model_provider = "custom"
          model = "{model}"
          disable_response_storage = true

          [model_providers.custom]
          name = "{provider_label} ({model})"
          base_url = "{target_base}"
          wire_api = "responses"
          requires_openai_auth = true
          """
                            cfg_codex = json.dumps({
                                "auth": {"OPENAI_API_KEY": target_key},
                                "config": toml_conf
                            })
                            cur.execute("""
                                INSERT OR REPLACE INTO providers (id, app_type, name, settings_config, website_url, category, created_at, sort_index, icon, icon_color, meta, is_current, in_failover_queue, cost_multiplier)
                                VALUES (?, 'codex', ?, ?, ?, 'aggregator', ?, ?, ?, ?, '{}', 0, 0, '1.0')
                            """, (f"{prefix}-codex-{model}", f"{provider_label} · {model}", cfg_codex, target_base, now_ms, sort_idx, icon, icon_color))

                    # 插入并设定优先级：CPA 设为最高优先级（sort_index 从 0 开始），玲碗作为备用（从 1000 开始）
                    if cpa_api_key:
                        insert_provider_models("cpa", "CPA", cpa_models, cpa_base, cpa_api_key, base_sort_index=0)
                    if api_key:
                        insert_provider_models("c5y", "玲碗", c5y_models, c5y_base, api_key, base_sort_index=1000)

                    # 激活 CPA 模型为默认选中项（最高优先级 is_current = 1）
                    cur.execute("UPDATE providers SET is_current = 0 WHERE 1=1")
                    cur.execute("""
                        UPDATE providers SET is_current = 1, in_failover_queue = 1
                        WHERE id = (
                            SELECT id FROM providers WHERE app_type = 'claude' AND id LIKE 'cpa-%'
                            ORDER BY CASE WHEN id LIKE '%sonnet%' THEN 0 ELSE 1 END, sort_index ASC LIMIT 1
                        ) AND app_type = 'claude'
                    """)
                    cur.execute("""
                        UPDATE providers SET is_current = 1, in_failover_queue = 1
                        WHERE id = (
                            SELECT id FROM providers WHERE app_type = 'gemini' AND id LIKE 'cpa-%'
                            ORDER BY CASE WHEN id LIKE '%flash%' THEN 0 ELSE 1 END, sort_index ASC LIMIT 1
                        ) AND app_type = 'gemini'
                    """)
                    cur.execute("""
                        UPDATE providers SET is_current = 1, in_failover_queue = 1
                        WHERE id = (
                            SELECT id FROM providers WHERE app_type = 'codex' AND id LIKE 'cpa-%'
                            ORDER BY CASE WHEN id LIKE '%120b%' THEN 0 WHEN id LIKE '%gpt%' THEN 1 ELSE 2 END, sort_index ASC LIMIT 1
                        ) AND app_type = 'codex'
                    """)

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
