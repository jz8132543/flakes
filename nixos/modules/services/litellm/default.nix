{ config, lib, ... }:
let
  cfg = config.services.ai.litellm;
in
{
  options.services.ai.litellm = {
    enable = lib.mkEnableOption "LiteLLM API Gateway Configuration";
  };

  config = lib.mkIf cfg.enable {

    # 1. Define SOPS secrets for Litellm
    # We load the secrets into an environment file that litellm systemd service reads.
    # The user should add these to secrets/common.yaml:
    # litellm:
    #   env: |
    #     GEMINI_API_KEY=xxx
    #     GITHUB_TOKEN=xxx
    #     OPENAI_API_KEY=xxx
    #     LITELLM_MASTER_KEY=sk-xxxx
    sops.secrets."litellm/env" = { };

    # 2. Configure LiteLLM
    services.litellm = {
      enable = true;
      port = 18790;
      environmentFile = config.sops.secrets."litellm/env".path;
      settings = {
        model_list = [
          {
            model_name = "gemini-2.0-flash";
            litellm_params = {
              model = "gemini/gemini-2.0-flash";
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
            model_name = "chatgpt-business";
            litellm_params = {
              model = "openai/gpt-4"; # Or whichever specific model version their business plan uses
              api_key = "os.environ/OPENAI_API_KEY";
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
        ];
        litellm_settings = {
          master_key = "os.environ/LITELLM_MASTER_KEY";
        };
        router_settings = {
          routing_strategy = "usage-based-routing";
        };
      };
    };

    # 3. Expose the LiteLLM UI/API via Traefik
    services.traefik.proxies = {
      litellm = {
        rule = "Host(`ai.${config.networking.domain}`)";
        target = "http://127.0.0.1:18790";
      };
    };

    # Allow litellm to persist the configuration DB (it creates litellm.db in CWD usually)
    # The default stateDir is /var/lib/litellm which is managed by systemd, so global persistence is fine if /var/lib is persisted.
  };
}
