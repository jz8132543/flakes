{ config, ... }:
{
  services.ollama = {
    enable = true;
    host = "0.0.0.0";
    port = config.ports.ollama-api;
  };
  services.open-webui = {
    enable = true;
    host = "0.0.0.0";
    port = config.ports.ollama-ui;
    environment = {
      ANONYMIZED_TELEMETRY = "False";
      DO_NOT_TRACK = "True";
      SCARF_NO_ANALYTICS = "True";
      OLLAMA_API_BASE_URL = "https://ollama.${config.networking.domain}/api";
      OLLAMA_BASE_URL = "https://ollama.${config.networking.domain}";
      # Disable authentication
      WEBUI_AUTH = "False";
      ENABLE_SIGNUP = "False";
      WEBUI_URL = "http://localhost:${toString config.ports.ollama-ui}";
      # Search
      ENABLE_RAG_WEB_SEARCH = "True";
      RAG_WEB_SEARCH_ENGINE = "searxng";
      SEARXNG_QUERY_URL = "https://searx.${config.networking.domain}/search?q=<query>";
      # fix crush on web search
      # RAG_EMBEDDING_ENGINE = "ollama";
      # RAG_EMBEDDING_MODEL = "mxbai-embed-large:latest";
      PYDANTIC_SKIP_VALIDATING_CORE_SCHEMAS = "True";
    };
  };
  # services.nextjs-ollama-llm-ui = {
  #   enable = true;
  #   hostname = "127.0.0.1";
  #   ollamaUrl = "https://ollama.${config.networking.domain}";
  #   port = 11435;
  # };
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      ollama-api = {
        rule = "Host(`ollama.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "ollama-api";
      };
      ollama-ui = {
        rule = "Host(`ollama-ui.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "ollama-ui";
      };
    };
    services = {
      ollama-api.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.ollama-api}"; } ];
      };
      ollama-ui.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.ollama-ui}"; } ];
      };
    };
  };
}
