{
  config,
  lib,
  inputs,
  ...
}:

let
  cfg = config.services.openclaw;
in
{
  options.services.openclaw = {
    enable = lib.mkEnableOption "OpenClaw AI Gateway service";
  };

  config = lib.mkIf cfg.enable {
    # 1. Overlay openclaw packages
    nixpkgs.overlays = [ inputs.openclaw-nix.overlays.default ];

    # 2. Define sops secrets
    sops.secrets = {
      "litellm/env" = {
        owner = "root";
      };
      "openclaw/gateway_token" = {
        owner = "openclaw";
      };
    };

    # 3. Dedicated system user for openclaw
    users.users.openclaw = {
      isSystemUser = true;
      group = "openclaw";
      extraGroups = [ "grafana" ];
      home = "/var/lib/openclaw";
      createHome = true;
    };
    users.groups.openclaw = { };

    # 5. Use the native NixOS module for the gateway
    services.openclaw-gateway = {
      enable = true;
      user = "openclaw";
      group = "openclaw";

      config = {
        gateway = {
          mode = "local";
          auth.token = "$__file{${config.sops.secrets."openclaw/gateway_token".path}}";
        };

        # Force all major providers to proxy through our local LiteLLM instance.
        providers = {
          openai = {
            api = "openai-responses";
            baseUrl = "http://127.0.0.1:18790/v1";
            apiKey = "sk-fast-secure-openclaw-key";
          };
          google = {
            api = "openai-responses";
            baseUrl = "http://127.0.0.1:18790/v1";
            apiKey = "sk-fast-secure-openclaw-key";
          };
          anthropic = {
            api = "openai-responses";
            baseUrl = "http://127.0.0.1:18790/v1";
            apiKey = "sk-fast-secure-openclaw-key";
          };
        };

        channels.telegram = {
          tokenFile = config.sops.secrets."telegram/token".path;
          dmPolicy = "allowlist";

          # Auto-authorize the user without pairing codes
          allowFrom = [ 629951492 ];
          groups = {
            "*" = {
              requireMention = true;
            };
          };
        };

        env.vars = {
          # These are standard env vars for openclaw internal drivers if they fallback
          OPENAI_BASE_URL = "http://127.0.0.1:18790/v1";
          OPENAI_API_KEY = "sk-fast-secure-openclaw-key";
          OPENCLAW_MODEL = "gemini-2.0-flash";
        };
      };
    };

    # 5. Expose the gateway UI/API via Traefik
    services.traefik.proxies = {
      openclaw = {
        rule = "Host(`claw.${config.networking.domain}`)";
        target = "http://127.0.0.1:18789";
      };
    };

    # 6. Ensure the directory is persistent and link personalities
    systemd.tmpfiles.rules = [
      "d /var/lib/openclaw/.openclaw 0750 openclaw openclaw -"
      "L+ /var/lib/openclaw/documents - - - - ${./documents}"
    ];
  };
}
