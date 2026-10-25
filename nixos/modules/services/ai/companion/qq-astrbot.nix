# ─────────────────────────────────────────────────────────────────────────────
# services/ai/companion/qq-astrbot.nix
#
# QQ 拟人多模态机器人全家桶 (NapCatQQ + AstrBot + dafeiyu-astrbot 架构)
#
# 架构：
#   QQ 客户端/群聊 ⇄ NapCat (无头 NTQQ, OneBot v11) ⇄ AstrBot (Agent 中枢) ⇄ New-API (本地算力/商业 API)
#
# 核心特性：
#   1. astrbot_plugin_face_convert：QQ 原生 [Face] 表情双向翻译、群聊身份隐式打标、多模态媒体抽取
#   2. 出站清洗：草稿箱 （（ ... ）） 撕毁剥离内心独白、嘴硬小尾巴拟人橡皮擦、标点归一
#   3. 直连本机 New-API (http://127.0.0.1:3280/v1) 与 arx8 本地大模型
#   4. 容器化 OCI (Podman) 隔离部署 + Impermanence 数据持久化
# ─────────────────────────────────────────────────────────────────────────────
{
  config,
  lib,
  pkgs,
  nixosModules,
  ...
}:
let
  cfg = config.services.ai.companion;
  qqCfg = cfg.qq;

  napcatWsPort = config.ports.napcat-ws;
  napcatWebuiPort = config.ports.napcat-webui;
  astrbotPort = config.ports.astrbot;

  baseDir = qqCfg.dataDir;
in
{
  imports = [
    nixosModules.services.podman
  ];

  config = lib.mkIf (cfg.enable && qqCfg.enable) {
    # ── 引用全局 SOPS 主密码 ──────────────────────────────────────────
    sops.secrets."password" = { };

    sops.templates."napcat-env".content = ''
      WEBUI_TOKEN=${config.sops.placeholder."password"}
    '';

    # ── 1. 预置基础目录与 NapCat / AstrBot 声明式凭据配置 ──────────────────
    systemd.services.dafeiyu-setup-dirs = {
      description = "Setup directories and default NapCat/AstrBot credentials";
      wantedBy = [ "multi-user.target" ];
      before = [
        "podman-napcat.service"
        "podman-astrbot.service"
      ];
      after = [ "sops-install-secrets.service" ];
      wants = [ "sops-install-secrets.service" ];
      path = with pkgs; [
        coreutils
        jq
        python3
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
                set -euo pipefail

                mkdir -p "${baseDir}/napcat/config" \
                         "${baseDir}/napcat/data" \
                         "${baseDir}/napcat/logs" \
                         "${baseDir}/astrbot/data/plugins" \
                         "${baseDir}/astrbot/data/personas" \
                         "${baseDir}/astrbot/data/knowledge"

                PASS="$(cat ${config.sops.secrets."password".path} | tr -d '\n\r')"

                # ── 自动将 NapCat WebUI Token 统一同步为 SOPS password ────────────
                NAPCAT_WEBUI="${baseDir}/napcat/config/webui.json"
                if [ -f "$NAPCAT_WEBUI" ]; then
                  jq --arg token "$PASS" '.token = $token' "$NAPCAT_WEBUI" > "$NAPCAT_WEBUI.tmp" && mv "$NAPCAT_WEBUI.tmp" "$NAPCAT_WEBUI"
                else
                  cat <<EOF > "$NAPCAT_WEBUI"
        {
          "host": "::",
          "port": ${toString napcatWebuiPort},
          "token": "$PASS",
          "loginRate": 10,
          "autoLoginAccount": "",
          "disableWebUI": false,
          "accessControlMode": "none"
        }
        EOF
                fi
                chmod 0644 "$NAPCAT_WEBUI"

                # ── 自动将 AstrBot Dashboard 账密同步为 用户名: i, 密码: SOPS password ──
                ASTRBOT_CONF="${baseDir}/astrbot/data/cmd_config.json"
                if [ -f "$ASTRBOT_CONF" ]; then
                  python3 - "$ASTRBOT_CONF" "$PASS" << 'PYEOF'
        import hashlib
        import json
        import secrets
        import sys

        conf_path = sys.argv[1]
        raw_pass = sys.argv[2]

        try:
            with open(conf_path, "r", encoding="utf-8-sig") as f:
                conf = json.load(f)
        except Exception:
            with open(conf_path, "r", encoding="utf-8") as f:
                conf = json.load(f)

        if "dashboard" not in conf:
            conf["dashboard"] = {}

        salt = secrets.token_hex(16)
        digest = hashlib.pbkdf2_hmac("sha256", raw_pass.encode("utf-8"), bytes.fromhex(salt), 600000).hex()
        pbkdf2_hash = "pbkdf2_sha256$600000$" + salt + "$" + digest
        md5_hash = hashlib.md5(raw_pass.encode("utf-8")).hexdigest()

        conf["dashboard"]["username"] = "i"
        conf["dashboard"]["password"] = md5_hash
        conf["dashboard"]["pbkdf2_password"] = pbkdf2_hash
        conf["dashboard"]["password_storage_upgraded"] = True
        conf["dashboard"]["password_change_required"] = False

        # ── 注入 ContextForge Chat 虚拟网关 ────────────────────────
        if "mcp_servers" not in conf:
            conf["mcp_servers"] = {}
        conf["mcp_servers"]["contextforge-chat"] = {
            "type": "sse",
            "url": "http://127.0.0.1:${toString config.ports.mcp-contextforge-api}/api/gateways/chat/sse",
            "headers": {
                "Authorization": f"Bearer {raw_pass}"
            }
        }

        with open(conf_path, "w", encoding="utf-8") as f:
            json.dump(conf, f, ensure_ascii=False, indent=2)

        print("[dafeiyu-setup] AstrBot dashboard credentials updated to username 'i'")
        PYEOF
                fi

                # ── 预置 NapCat OneBot v11 默认网络配置文件 ────────────────────
                NAPCAT_OB11="${baseDir}/napcat/config/onebot11.json"
                if [ ! -f "$NAPCAT_OB11" ]; then
                  cat <<EOF > "$NAPCAT_OB11"
        {
          "http": {
            "enable": false,
            "host": "127.0.0.1",
            "port": 3000,
            "secret": ""
          },
          "ws": {
            "enable": true,
            "host": "127.0.0.1",
            "port": ${toString napcatWsPort},
            "secret": ""
          },
          "reverseWs": {
            "enable": true,
            "urls": [
              "ws://127.0.0.1:6199/ws"
            ]
          },
          "GroupLocalTime": {
            "Record": false,
            "RecordList": []
          },
          "debug": false,
          "heartInterval": 30000,
          "messagePostFormat": "array",
          "enableQrcodeLogin": true
        }
        EOF
                  chmod 0644 "$NAPCAT_OB11"
                fi

                # ── 3. 部署 AstrBot 人设切换与管理插件 (可在 QQ 发送 /persona 切换) ──
                PERSONA_PLUGIN_DIR="${baseDir}/astrbot/data/plugins/astrbot_plugin_persona"
                mkdir -p "$PERSONA_PLUGIN_DIR"
                cat << 'EOF' > "$PERSONA_PLUGIN_DIR/main.py"
        import httpx
        from astrbot.api.event import AstrMessageEvent, filter
        from astrbot.api.star import Context, Star, register

        PERSONA_ENGINE = "http://127.0.0.1:5006"

        @register("astrbot_plugin_persona", "Tippy", "切换与查看 Persona Engine 角色人设", "1.0.0")
        class PersonaPlugin(Star):
            def __init__(self, context: Context):
                super().__init__(context)

            @filter.command("persona")
            async def persona_cmd(self, event: AstrMessageEvent, name: str = ""):
                """查看或切换当前陪伴人设。用法：/persona 或 /persona <人设名称>"""
                name = name.strip()
                async with httpx.AsyncClient(timeout=10.0) as client:
                    if not name or name == "list":
                        try:
                            r = await client.get(f"{PERSONA_ENGINE}/v1/personas")
                            if r.status_code == 200:
                                data = r.json()
                                active = data.get("active", "")
                                personas = data.get("personas", [])
                                lines = ["🎭 【Persona Engine 角色人设库】"]
                                for i, p in enumerate(personas, 1):
                                    pname = p.get("name", "")
                                    is_act = " [⭐当前激活]" if pname == active else ""
                                    desc = p.get("description", "")[:50]
                                    lines.append(f"{i}. {pname}{is_act}\n   {desc}...")
                                lines.append("\n👉 发送 /persona <人设名称> 即可即刻切换当前人格！")
                                yield event.plain_result("\n".join(lines))
                            else:
                                yield event.plain_result("无法连接到 Persona Engine，请检查服务状态。")
                        except Exception as e:
                            yield event.plain_result(f"获取人设列表失败: {e}")
                    else:
                        try:
                            r = await client.post(f"{PERSONA_ENGINE}/v1/personas/select", params={"name": name})
                            if r.status_code == 200:
                                yield event.plain_result(f"✅ 人格切换成功！当前激活人设已变为：【{name}】")
                            else:
                                yield event.plain_result(f"❌ 切换失败：未找到名为【{name}】的人设。可输入 /persona 查看可用列表。")
                        except Exception as e:
                            yield event.plain_result(f"请求切换失败: {e}")
        EOF
                chmod 0644 "$PERSONA_PLUGIN_DIR/main.py"
      '';
    };

    # ── 首次部署若尚未生成 cmd_config.json，容器启动后自动补齐账密同步 ───────
    systemd.services.astrbot-auth-sync = {
      description = "Ensure AstrBot dashboard credentials match username 'i' and SOPS password";
      after = [ "podman-astrbot.service" ];
      wants = [ "podman-astrbot.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = with pkgs; [
        coreutils
        python3
        systemd
      ];
      script = ''
                set -euo pipefail
                PASS="$(cat ${config.sops.secrets."password".path} | tr -d '\n\r')"
                ASTRBOT_CONF="${baseDir}/astrbot/data/cmd_config.json"

                # 等待 AstrBot 容器初始化生成 cmd_config.json
                for i in $(seq 1 30); do
                  if [ -f "$ASTRBOT_CONF" ]; then
                    break
                  fi
                  sleep 1
                done

                if [ -f "$ASTRBOT_CONF" ]; then
                  UPDATED="$(python3 - "$ASTRBOT_CONF" "$PASS" << 'PYEOF'
        import hashlib
        import json
        import secrets
        import sys

        conf_path = sys.argv[1]
        raw_pass = sys.argv[2]

        try:
            with open(conf_path, "r", encoding="utf-8-sig") as f:
                conf = json.load(f)
        except Exception:
            with open(conf_path, "r", encoding="utf-8") as f:
                conf = json.load(f)

        d = conf.get("dashboard", {})
        salt = secrets.token_hex(16)
        digest = hashlib.pbkdf2_hmac("sha256", raw_pass.encode("utf-8"), bytes.fromhex(salt), 600000).hex()
        target_pbkdf2 = "pbkdf2_sha256$600000$" + salt + "$" + digest
        target_md5 = hashlib.md5(raw_pass.encode("utf-8")).hexdigest()

        if d.get("username") != "i" or not d.get("pbkdf2_password") or d.get("password_change_required") or "contextforge-chat" not in conf.get("mcp_servers", {}):
            d["username"] = "i"
            d["password"] = target_md5
            d["pbkdf2_password"] = target_pbkdf2
            d["password_storage_upgraded"] = True
            d["password_change_required"] = False
            conf["dashboard"] = d
            if "mcp_servers" not in conf:
                conf["mcp_servers"] = {}
            conf["mcp_servers"]["contextforge-chat"] = {
                "type": "sse",
                "url": "http://127.0.0.1:${toString config.ports.mcp-contextforge-api}/api/gateways/chat/sse",
                "headers": {
                    "Authorization": f"Bearer {raw_pass}"
                }
            }
            with open(conf_path, "w", encoding="utf-8") as f:
                json.dump(conf, f, ensure_ascii=False, indent=2)
            print("changed")
        else:
            print("unchanged")
        PYEOF
        )"
                  if [ "$UPDATED" = "changed" ]; then
                    echo "[astrbot-auth-sync] Credentials updated to username 'i', restarting AstrBot container..."
                    systemctl restart podman-astrbot.service || true
                  fi
                fi
      '';
    };

    # ── 2. OCI 容器编排：NapCatQQ 与 AstrBot ─────────────────────────
    virtualisation.oci-containers.containers = {
      # ── NapCatQQ (无头 NTQQ 协议端) ──────────────────────────────
      napcat = {
        image = qqCfg.napcatImage;
        autoStart = true;
        extraOptions = [
          "--network=host"
        ];
        environment = {
          ACCOUNT = qqCfg.account;
          NAPCAT_QUICK_ACCOUNT = qqCfg.account;
          HTTP_ENABLE = "false";
          WS_ENABLE = "true";
          WS_PORT = toString napcatWsPort;
          WEBUI_ENABLE = "true";
          WEBUI_PORT = toString napcatWebuiPort;
          NAPCAT_GID = "0";
          NAPCAT_UID = "0";
        };
        environmentFiles = [
          config.sops.templates."napcat-env".path
        ];
        volumes = [
          "${baseDir}/napcat/config:/app/napcat/config"
          "${baseDir}/napcat/data:/app/.config/QQ"
          "${baseDir}/napcat/logs:/app/napcat/logs"
        ];
      };

      # ── AstrBot (智能体认知调度中枢) ─────────────────────────────
      astrbot = {
        image = qqCfg.astrbotImage;
        autoStart = true;
        extraOptions = [
          "--network=host"
        ];
        environment = {
          PORT = toString astrbotPort;
          ASTRBOT_PORT = toString astrbotPort;
          TZ = config.time.timeZone;
        };
        volumes = [
          "${baseDir}/astrbot/data:/AstrBot/data"
        ];
      };
    };

    # ── 3. Systemd 依赖拓扑 ──────────────────────────────────────────
    systemd.services.podman-napcat = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.podman-astrbot = {
      after = [
        "network-online.target"
        "dafeiyu-setup-dirs.service"
        "podman-napcat.service"
        "podman-new-api.service"
      ];
      requires = [
        "dafeiyu-setup-dirs.service"
        "podman-napcat.service"
      ];
      wantedBy = [ "multi-user.target" ];
    };

    # ── 4. 自愈辅助工具 (通过 NapCat WebUI 刷新连接，不重启容器、不退登) ───────
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "heal-napcat-ws" ''
        set -euo pipefail
        CONFIG="${baseDir}/napcat/config/webui.json"
        if [ ! -f "$CONFIG" ]; then
          echo "NapCat webui config not found at $CONFIG"
          exit 1
        fi
        TOKEN="$(jq -r '.token // empty' "$CONFIG")"
        if [ -z "$TOKEN" ]; then
          echo "NapCat token not found in $CONFIG"
          exit 1
        fi
        HASH="$(printf '%s.napcat' "$TOKEN" | sha256sum | awk '{print $1}')"
        echo "[heal-napcat-ws] Logging into NapCat WebUI..."
        LOGIN_RESP="$(curl -s -f -X POST "http://127.0.0.1:${toString napcatWebuiPort}/api/auth/login" \
          -H "Content-Type: application/json" \
          -d "{\"hash\":\"$HASH\"}")"
        CRED="$(printf '%s' "$LOGIN_RESP" | jq -r '.data.Credential')"
        if [ -z "$CRED" ] || [ "$CRED" = "null" ]; then
          echo "Failed to get NapCat credentials"
          exit 1
        fi
        echo "[heal-napcat-ws] Resetting OneBot WebSocket connections..."
        CFG="$(curl -s -f -H "Authorization: Bearer $CRED" "http://127.0.0.1:${toString napcatWebuiPort}/api/OB11Config/GetConfig" | jq '.data')"
        DISABLED_CFG="$(echo "$CFG" | jq '.network.websocketClients = (.network.websocketClients | map(.enable = false))')"
        curl -s -f -X POST "http://127.0.0.1:${toString napcatWebuiPort}/api/OB11Config/SetConfig" \
          -H "Authorization: Bearer $CRED" -H "Content-Type: application/json" \
          -d "{\"config\": $(echo "$DISABLED_CFG" | jq -R .)}" >/dev/null
        sleep 2
        ENABLED_CFG="$(echo "$CFG" | jq '.network.websocketClients = (.network.websocketClients | map(.enable = true))')"
        curl -s -f -X POST "http://127.0.0.1:${toString napcatWebuiPort}/api/OB11Config/SetConfig" \
          -H "Authorization: Bearer $CRED" -H "Content-Type: application/json" \
          -d "{\"config\": $(echo "$ENABLED_CFG" | jq -R .)}" >/dev/null
        echo "[heal-napcat-ws] WebSocket clients refreshed successfully without restarting container."
      '')
    ];
  };
}
