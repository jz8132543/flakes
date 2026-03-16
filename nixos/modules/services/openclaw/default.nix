{
  config,
  lib,
  inputs,
  ...
}:

let
  cfg = config.services.openclaw;
  proxyApiKeyRef = "$__file{${config.sops.secrets."openclaw/api_key".path}}";
  gatewayTokenRef = "$__file{${config.sops.secrets."openclaw/gateway_token".path}}";
  qqAppIdRef = "$__file{${config.sops.secrets."openclaw/qq/app_id".path}}";
  qqAppSecretRef = "$__file{${config.sops.secrets."openclaw/qq/app_secret".path}}";
  qqTokenRef = "$__file{${config.sops.secrets."openclaw/qq/token".path}}";
  qqBotIdRef = "$__file{${config.sops.secrets."openclaw/qq/bot_id".path}}";
  upstreamBaseUrl =
    if cfg.upstreamBaseUrl != null then
      cfg.upstreamBaseUrl
    else
      lib.attrByPath [
        "services"
        "ai"
        "litellm"
        "publicBaseUrl"
      ] "https://ai.${config.networking.domain}/v1" config;
  baseGatewayConfig = {
    gateway = {
      mode = "local";
      bind = "loopback";
      auth.token = gatewayTokenRef;
    }
    // lib.optionalAttrs cfg.panel.enable {
      controlUi.enabled = true;
    };

    channels = lib.optionalAttrs cfg.telegram.enable {
      telegram = {
        tokenFile = config.sops.secrets."telegram/token".path;
        dmPolicy = "allowlist";
        inherit (cfg.telegram) allowFrom;
        groups = {
          "*" = {
            inherit (cfg.telegram) requireMention;
          };
        };
      };
    };

    commands = {
      ownerAllowFrom = cfg.telegram.allowFrom;
      useAccessGroups = true;
    };

    messages = {
      queue = {
        mode = "steer-backlog";
        cap = 24;
      };
      suppressToolErrors = false;
    };

    env.vars = {
      OPENAI_BASE_URL = upstreamBaseUrl;
      OPENAI_API_KEY = proxyApiKeyRef;
      OPENCLAW_MODEL = cfg.model;
    };
  };
in
{
  options.services.openclaw = {
    enable = lib.mkEnableOption "OpenClaw AI Gateway service";
    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "claw";
      description = "Subdomain used for the OpenClaw gateway route.";
    };
    model = lib.mkOption {
      type = lib.types.str;
      default = "gemini-2.0-flash";
      description = "Default model name exposed to OpenClaw.";
    };
    upstreamBaseUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "LiteLLM OpenAI-compatible base URL. Default is services.ai.litellm.publicBaseUrl.";
    };
    panel = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable OpenClaw control UI panel.";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "claw-panel";
        description = "Subdomain for OpenClaw control UI.";
      };
    };
    telegram = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Telegram channel for OpenClaw.";
      };
      allowFrom = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [ 629951492 ];
        description = "Telegram user IDs allowed to use privileged OpenClaw operations.";
      };
      requireMention = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Require mention in Telegram groups.";
      };
    };
    qqBot = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Reserve QQ bot credentials and inject QQ env vars for bridge integrations.";
      };
      sandbox = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether QQ bot should run in sandbox mode.";
      };
    };
    extraGatewayConfig = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional OpenClaw gateway config merged deeply into defaults.";
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [ inputs.openclaw-nix.overlays.default ];

    sops.secrets = {
      "openclaw/gateway_token" = {
        owner = "openclaw";
        group = "openclaw";
        mode = "0440";
      };
      "openclaw/api_key" = {
        owner = "openclaw";
        group = "openclaw";
        mode = "0440";
      };
    }
    // lib.optionalAttrs cfg.qqBot.enable {
      # QQ currently needs an external bridge in this pinned OpenClaw release.
      # We keep credentials in sops and inject env vars to make bridge deployment zero-friction.
      "openclaw/qq/app_id" = {
        owner = "openclaw";
        group = "openclaw";
        mode = "0440";
      };
      "openclaw/qq/app_secret" = {
        owner = "openclaw";
        group = "openclaw";
        mode = "0440";
      };
      "openclaw/qq/token" = {
        owner = "openclaw";
        group = "openclaw";
        mode = "0440";
      };
      "openclaw/qq/bot_id" = {
        owner = "openclaw";
        group = "openclaw";
        mode = "0440";
      };
    };

    users.users.openclaw.extraGroups = [ "grafana" ];
    users.groups.openclaw = { };

    services.openclaw-gateway = {
      enable = true;
      user = "openclaw";
      group = "openclaw";
      restartSec = 3;
      config = lib.recursiveUpdate baseGatewayConfig cfg.extraGatewayConfig;
      environment = lib.optionalAttrs cfg.qqBot.enable {
        OPENCLAW_QQ_APP_ID = qqAppIdRef;
        OPENCLAW_QQ_APP_SECRET = qqAppSecretRef;
        OPENCLAW_QQ_TOKEN = qqTokenRef;
        OPENCLAW_QQ_BOT_ID = qqBotIdRef;
        OPENCLAW_QQ_SANDBOX = if cfg.qqBot.sandbox then "true" else "false";
      };
    };

    systemd.services.openclaw-gateway = {
      after = [
        "network-online.target"
        "litellm.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = lib.mkDefault false;
        ProtectKernelTunables = lib.mkDefault false;
        ProtectKernelModules = lib.mkDefault false;
        ProtectControlGroups = lib.mkDefault false;
        ProtectClock = lib.mkDefault false;
        ProtectHostname = lib.mkDefault false;
        RestrictSUIDSGID = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        UMask = "0077";
      };
    };

    services.traefik.proxies = {
      openclaw = {
        rule = "Host(`${cfg.subdomain}.${config.networking.domain}`)";
        target = "http://127.0.0.1:18789";
      };
    }
    // lib.optionalAttrs cfg.panel.enable {
      openclaw-panel = {
        rule = "Host(`${cfg.panel.subdomain}.${config.networking.domain}`)";
        target = "http://127.0.0.1:18789";
      };
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/openclaw/.openclaw 0750 openclaw openclaw -"
      "L+ /var/lib/openclaw/documents - - - - ${./documents}"
    ];
  };
}
