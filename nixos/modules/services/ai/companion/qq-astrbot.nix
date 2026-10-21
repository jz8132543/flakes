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
    # ── 1. 预置基础目录与 NapCat OneBot v11 网络配置 ─────────────────────
    systemd.services.dafeiyu-setup-dirs = {
      description = "Setup directories and default NapCat network config";
      wantedBy = [ "multi-user.target" ];
      before = [
        "podman-napcat.service"
        "podman-astrbot.service"
      ];
      path = with pkgs; [
        coreutils
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
