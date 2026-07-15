{
  config,
  nixosModules,
  pkgs,
  ...
}:
let
  domain = "chat.dora.im";
  port = config.ports.lobechat;
  dbName = "lobechat";
  dbUser = "lobechat";
  dbHost = "127.0.0.1";
  storage = config.lib.self.data.lobechat.storage;
in
{
  imports = [
    nixosModules.services.podman
    nixosModules.services.postgres
    nixosModules.services.traefik
  ];

  sops.secrets = {
    "lobechat/auth_secret" = { };
    "lobechat/keycloak_client_secret" = { };
    "lobechat/OPENAI_API_KEY" = { };
    "lobechat/OPENAI_PROXY_URL" = { };
    "lobechat/jwks_key" = { };
    "lobechat/b2_key_id" = {
      restartUnits = [ "podman-lobechat.service" ];
    };
    "lobechat/b2_access_key" = {
      restartUnits = [ "podman-lobechat.service" ];
    };
  };

  virtualisation.oci-containers.containers.lobechat = {
    image = "lobehub/lobehub:latest";
    autoStart = true;
    extraOptions = [
      "--network=host"
      "--pull=missing"
    ];
    environment = {
      APP_URL = "https://${domain}";
      DATABASE_URL = "postgresql://${dbUser}@${dbHost}:5432/${dbName}";
      PORT = toString port;
      NEXT_PUBLIC_ENABLE_WELCOMES = "false";
      AUTH_SSO_PROVIDERS = "keycloak";
      AUTH_KEYCLOAK_ID = "lobechat";
      AUTH_KEYCLOAK_ISSUER = "https://sso.dora.im/realms/users";
      S3_BUCKET = storage.bucket;
      S3_ENABLE_PATH_STYLE = "1";
      S3_ENDPOINT = storage.endpoint;
      S3_PUBLIC_DOMAIN = storage.publicDomain;
      S3_REGION = storage.region;
      S3_SET_ACL = "0";
      FEATURE_FLAGS = "-changelog,-check_updates,-welcome_suggest,+market,+plugins,+knowledge_base,+group_chat,+dalle,+speech_to_text,+webrtc_sync,+openai_api_key,+openai_proxy_url,+provider_settings,+api_key_manage";
      ENABLED_ARTIFACTS = "1";
      ENABLED_MCP = "1";
      ENABLED_UPLOAD = "1";
      PLUGINS_INDEX_URL = "https://registry.npmmirror.com/@lobehub/plugins-index/v1/files/public";
      AGENTS_INDEX_URL = "https://chat-agents.lobehub.com";

      # OPENAI_MODEL_LIST is generated dynamically by lobechat-fetch-models.service

      # Disable other unused provider tabs
      ENABLED_DEEPSEEK = "0";
      ENABLED_ZHIPU = "0";
      ENABLED_MOONSHOT = "0";
      ENABLED_GOOGLE = "0";
      ENABLED_ANTHROPIC = "0";
      ENABLED_GROQ = "0";
      ENABLED_OPENROUTER = "0";
      ENABLED_MISTRAL = "0";
      ENABLED_PERPLEXITY = "0";
      ENABLED_TOGETHERAI = "0";
      ENABLED_BAICHUAN = "0";
      ENABLED_MINIMAX = "0";
      ENABLED_ZEROONE = "0";
      ENABLED_QWEN = "0";
      ENABLED_SPARK = "0";
      ENABLED_HUGGINGFACE = "0";
      ENABLED_AWS = "0";
      ENABLED_AZURE = "0";
      ENABLED_COHERE = "0";
      ENABLED_HUNYUAN = "0";
      ENABLED_SENSENOVA = "0";
      ENABLED_STEPFUN = "0";
      ENABLED_BAIDU = "0";
      ENABLED_AI360 = "0";
      ENABLED_OLLAMA = "0";
      ENABLED_NOVITA = "0";
      ENABLED_TOGETHER = "0";
      ENABLED_VERTEX = "0";
      ENABLED_XAI = "0";
      ENABLED_FAL = "0";
      ENABLED_SILICONCLOUD = "0";
    };
    environmentFiles = [
      config.sops.templates."lobechat-env".path
      "/run/lobechat-models.env"
    ];
    volumes = [
      "/var/lib/lobechat:/app/data"
    ];
  };

  systemd.services.podman-lobechat = {
    after = [
      "lobechat-db-init.service"
      "lobechat-fetch-models.service"
    ];
    requires = [
      "lobechat-db-init.service"
      "lobechat-fetch-models.service"
    ];
  };

  systemd.services.lobechat-db-init = {
    description = "Initialize LobeChat PostgreSQL extensions";
    after = [
      "postgresql.service"
      "postgresql-setup.service"
    ];
    requires = [
      "postgresql.service"
      "postgresql-setup.service"
    ];
    before = [ "podman-lobechat.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.postgresql}/bin/psql \
        --dbname=${dbName} \
        --set=ON_ERROR_STOP=1 \
        --command='CREATE EXTENSION IF NOT EXISTS vector; CREATE EXTENSION IF NOT EXISTS pg_search;'

      # Remove stale per-user provider records for disabled providers so they
      # do not reappear in the UI despite ENABLED_* = "0" env vars.
      ${pkgs.postgresql}/bin/psql \
        --dbname=${dbName} \
        --command="DELETE FROM ai_providers WHERE id IN ('deepseek','google','anthropic','zhipu','moonshot','groq','openrouter','mistral','perplexity','togetherai','baichuan','minimax','zeroone','qwen','spark','huggingface','aws','azure','cohere','hunyuan','sensenova','stepfun','baidu','ai360','ollama','novita','together','vertex','xai','fal','siliconcloud','comfyui');" 2>/dev/null || true
    '';
  };

  sops.templates."lobechat-env".content = ''
    AUTH_SECRET=${config.sops.placeholder."lobechat/auth_secret"}
    AUTH_KEYCLOAK_SECRET=${config.sops.placeholder."lobechat/keycloak_client_secret"}
    KEY_VAULTS_SECRET=${config.sops.placeholder."lobechat/auth_secret"}
    JWKS_KEY=${config.sops.placeholder."lobechat/jwks_key"}
    S3_ACCESS_KEY_ID=${config.sops.placeholder."lobechat/b2_key_id"}
    S3_SECRET_ACCESS_KEY=${config.sops.placeholder."lobechat/b2_access_key"}
    OPENAI_PROXY_URL=${config.sops.placeholder."lobechat/OPENAI_PROXY_URL"}
    OPENAI_API_KEY=${config.sops.placeholder."lobechat/OPENAI_API_KEY"}
  '';

  # Dynamically fetch the model list from the OpenAI-compatible proxy before
  # LobeChat starts, so all available models are pre-enabled without hardcoding.
  systemd.services.lobechat-fetch-models = {
    description = "Fetch available models from OpenAI proxy for LobeChat";
    after = [
      "network-online.target"
      "sops-install-secrets.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "sops-install-secrets.service" ];
    before = [ "podman-lobechat.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      SECRETS_FILE=${config.sops.templates."lobechat-env".path}
      PROXY_URL=$(${pkgs.gnugrep}/bin/grep '^OPENAI_PROXY_URL=' "$SECRETS_FILE" | ${pkgs.coreutils}/bin/cut -d= -f2-)
      API_KEY=$(${pkgs.gnugrep}/bin/grep '^OPENAI_API_KEY=' "$SECRETS_FILE" | ${pkgs.coreutils}/bin/cut -d= -f2-)

      if [ -z "$PROXY_URL" ] || [ -z "$API_KEY" ]; then
        echo "lobechat-fetch-models: missing OPENAI_PROXY_URL or OPENAI_API_KEY, skipping" >&2
        echo "OPENAI_MODEL_LIST=" > /run/lobechat-models.env
        exit 0
      fi

      MODEL_IDS=$(${pkgs.curl}/bin/curl -sf --max-time 30 \
        -H "Authorization: Bearer $API_KEY" \
        "$PROXY_URL/models" \
        | ${pkgs.jq}/bin/jq -r '[.data[].id] | map("+" + .) | join(",")' 2>/dev/null || true)

      if [ -n "$MODEL_IDS" ]; then
        echo "OPENAI_MODEL_LIST=$MODEL_IDS" > /run/lobechat-models.env
        echo "lobechat-fetch-models: fetched $(echo "$MODEL_IDS" | tr ',' '\n' | wc -l) models"
      else
        echo "lobechat-fetch-models: could not fetch model list, writing empty list" >&2
        echo "OPENAI_MODEL_LIST=" > /run/lobechat-models.env
      fi
    '';
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/lobechat 0750 root root -"
    "f /run/lobechat-models.env 0644 root root -"
  ];

  services.traefik.proxies.lobechat = {
    rule = "Host(`${domain}`)";
    target = "http://127.0.0.1:${toString port}";
  };
}
