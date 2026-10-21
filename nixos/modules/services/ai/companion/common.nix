# ─────────────────────────────────────────────────────────────────────────────
# services/ai/companion/common.nix
#
# AI 情绪陪伴人设引擎 — 通用配置、数据持久化与反向代理
# ─────────────────────────────────────────────────────────────────────────────
{
  config,
  lib,
  nixosModules,
  ...
}:
let
  cfg = config.services.ai.companion;
in
{
  imports = [
    nixosModules.services.traefik
    nixosModules.services.restic
  ];

  options.services.ai.companion = {
    enable = lib.mkEnableOption "AI Emotional Companion and Persona Architecture";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "persona.${config.networking.domain}";
      description = "Public domain for Persona Engine API.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = config.ports.persona-engine;
      description = "Listen port for Persona Engine API.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/ai-companion";
      description = "Data directory for personas, character cards, and conversation memory.";
    };

    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "gemini-3-flash";
      description = "Default LLM model to route requests through New-API.";
    };

    defaultUser = lib.mkOption {
      type = lib.types.str;
      default = "Tippy";
      description = "Default username for macro expansion in persona cards.";
    };

    upstreamApiBase = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:${toString config.ports.new-api}/v1";
      description = "New-API or OpenAI-compatible backend base URL.";
    };

    # ── QQ 机器人 (NapCat + AstrBot + dafeiyu 全家桶) ─────────────────
    qq = {
      enable = lib.mkEnableOption "QQ Robot integration via NapCat and AstrBot (dafeiyu-astrbot runtime)";

      domain = lib.mkOption {
        type = lib.types.str;
        default = "bot.${config.networking.domain}";
        description = "Public domain for AstrBot WebUI management panel.";
      };

      napcatDomain = lib.mkOption {
        type = lib.types.str;
        default = "napcat.${config.networking.domain}";
        description = "Public domain for NapCat WebUI login & QR code scanner.";
      };

      account = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Robot QQ Account number (leave empty on initial deployment for QR code scan).";
      };

      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/dafeiyu";
        description = "Root data directory for NapCat credentials and AstrBot state.";
      };

      napcatImage = lib.mkOption {
        type = lib.types.str;
        default = "docker.io/mlikiowa/napcat-docker:v4.18.37";
        description = "Container image for NapCat (OneBot v11 NTQQ protocol).";
      };

      astrbotImage = lib.mkOption {
        type = lib.types.str;
        default = "docker.io/soulter/astrbot:v4.29.0";
        description = "Container image for AstrBot agent core runtime.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      # ── 数据目录与状态持久化 ─────────────────────────────────────────
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir}                  0755 root root - -"
        "d ${cfg.dataDir}/personas         0755 root root - -"
        "d ${cfg.dataDir}/memory           0755 root root - -"
      ];

      environment.global-persistence.directories = [
        cfg.dataDir
      ];

      services.restic.backups.borgbase.paths = [
        cfg.dataDir
      ];

      # Traefik 反向代理
      services.traefik.proxies.ai-persona = {
        rule = "Host(`${cfg.domain}`)";
        target = "http://127.0.0.1:${toString cfg.port}";
      };
    })

    (lib.mkIf (cfg.enable && cfg.qq.enable) {
      # ── QQ 机器人数据目录与 Impermanence 持久化 ───────────────────────
      systemd.tmpfiles.rules = [
        "d ${cfg.qq.dataDir}                     0755 root root - -"
        "d ${cfg.qq.dataDir}/napcat/config       0755 root root - -"
        "d ${cfg.qq.dataDir}/napcat/data         0755 root root - -"
        "d ${cfg.qq.dataDir}/astrbot/data        0755 root root - -"
      ];

      environment.global-persistence.directories = [
        cfg.qq.dataDir
      ];

      # ── 5GB 极简灾备：排除大量 QQ 接收的缓存多媒体图片与视频 ─────────
      services.restic.backups.borgbase = {
        paths = lib.mkAfter [
          "${cfg.qq.dataDir}/napcat/config"
          "${cfg.qq.dataDir}/astrbot/data"
        ];
        exclude = lib.mkAfter [
          "**/napcat/data/**/ChatMsg/**"
          "**/napcat/data/**/Audio/**"
          "**/napcat/data/**/Video/**"
          "**/napcat/data/**/Pic/**"
          "**/napcat/data/**/OriPic/**"
          "${cfg.qq.dataDir}/**/logs/**"
          "${cfg.qq.dataDir}/**/temp/**"
          "${cfg.qq.dataDir}/**/cache/**"
          "${cfg.qq.dataDir}/**/__pycache__/**"
        ];
      };

      # Traefik 反向代理：AstrBot 管理后台与 NapCat 扫码控制面板
      services.traefik.proxies = {
        astrbot = {
          rule = "Host(`${cfg.qq.domain}`)";
          target = "http://127.0.0.1:${toString config.ports.astrbot}";
        };
        napcat = {
          rule = "Host(`${cfg.qq.napcatDomain}`)";
          target = "http://127.0.0.1:${toString config.ports.napcat-webui}";
        };
      };
    })
  ];
}
