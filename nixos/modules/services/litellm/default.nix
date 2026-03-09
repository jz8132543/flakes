{ config, lib, ... }:
let
  cfg = config.services.ai.litellm;
  runtimeEnvFile = "${cfg.stateDir}/runtime.env";
in
{
  options.services.ai.litellm = {
    enable = lib.mkEnableOption "LiteLLM API Gateway Configuration";
    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind host for LiteLLM.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 18790;
      description = "Bind port for LiteLLM.";
    };
    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "ai";
      description = "Traefik subdomain for LiteLLM public endpoint.";
    };
    publicBaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://${cfg.subdomain}.${config.networking.domain}/v1";
      description = "Public OpenAI-compatible base URL for clients/OpenClaw.";
    };
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/litellm";
      description = "State directory for LiteLLM runtime env/db.";
    };
    githubCopilot = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable GitHub Copilot provider in LiteLLM.";
      };
      tokenDir = lib.mkOption {
        type = lib.types.str;
        default = "${cfg.stateDir}/github-copilot";
        description = "Token dir used by LiteLLM github_copilot authenticator.";
      };
      alias = lib.mkOption {
        type = lib.types.str;
        default = "copilot-gpt-4.1";
        description = "Model alias exposed by LiteLLM for GitHub Copilot.";
      };
      model = lib.mkOption {
        type = lib.types.str;
        default = "github_copilot/gpt-4.1";
        description = "Upstream github_copilot model identifier.";
      };
    };
    modelList = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [
        {
          model_name = "gemini-2.0-flash";
          litellm_params = {
            model = "gemini/gemini-2.0-flash";
            api_key = "os.environ/GEMINI_API_KEY";
          };
        }
        {
          model_name = "gemini-2.5-flash";
          litellm_params = {
            model = "gemini/gemini-2.5-flash";
            api_key = "os.environ/GEMINI_API_KEY";
          };
        }
        {
          model_name = "gpt-4o";
          litellm_params = {
            model = "openai/gpt-4o";
            api_base = "https://models.inference.ai.azure.com";
            api_key = "os.environ/GITHUB_TOKEN";
          };
        }
        {
          model_name = "gpt-4o-mini";
          litellm_params = {
            model = "openai/gpt-4o-mini";
            api_base = "https://models.inference.ai.azure.com";
            api_key = "os.environ/GITHUB_TOKEN";
          };
        }
        {
          model_name = "claude-sonnet-4-5";
          litellm_params = {
            model = "anthropic/claude-sonnet-4-5-20250929";
            api_key = "os.environ/ANTHROPIC_API_KEY";
          };
        }
      ]
      ++ lib.optional cfg.githubCopilot.enable {
        model_name = cfg.githubCopilot.alias;
        litellm_params = {
          inherit (cfg.githubCopilot) model;
        };
      };
      description = "LiteLLM model_list.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."litellm/env" = {
      owner = "root";
      mode = "0400";
    };

    systemd.services.litellm-env-prepare = {
      description = "Prepare LiteLLM runtime environment file";
      wantedBy = [ "multi-user.target" ];
      before = [ "litellm.service" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        set -euo pipefail
        install -d -m 0750 ${cfg.stateDir}
        ${lib.optionalString cfg.githubCopilot.enable ''
          # Migrate old root-owned token dir created by previous config.
          if [ -d ${cfg.githubCopilot.tokenDir} ] && [ "$(stat -c '%u' ${cfg.githubCopilot.tokenDir})" = "0" ]; then
            rm -rf ${cfg.githubCopilot.tokenDir}
          fi
        ''}
        cat ${config.sops.secrets."litellm/env".path} > ${runtimeEnvFile}
        chmod 0640 ${runtimeEnvFile}
      '';
    };

    services.litellm = {
      enable = true;
      inherit (cfg)
        host
        port
        ;
      environment = lib.optionalAttrs cfg.githubCopilot.enable {
        GITHUB_COPILOT_TOKEN_DIR = cfg.githubCopilot.tokenDir;
      };
      environmentFile = runtimeEnvFile;
      settings = {
        model_list = cfg.modelList;
        litellm_settings = {
          master_key = "os.environ/LITELLM_MASTER_KEY";
        };
        router_settings = {
          routing_strategy = "usage-based-routing";
        };
      };
    };

    systemd.services.litellm = {
      requires = [ "litellm-env-prepare.service" ];
      after = [ "litellm-env-prepare.service" ];
      serviceConfig = {
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectControlGroups = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        RestrictSUIDSGID = true;
      };
    };

    services.traefik.proxies = {
      litellm = {
        rule = "Host(`${cfg.subdomain}.${config.networking.domain}`)";
        target = "http://${cfg.host}:${toString cfg.port}";
      };
    };
  };
}
