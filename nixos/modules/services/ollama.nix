{ config, ... }:
{
  services = {
    ollama = {
      enable = true;
      loadModels = [
        "deepseek-r1:7B"
        "deepseek-r1:14B"
      ];
      port = config.ports.ollama-api;
    };
    open-webui = {
      enable = true;
      host = "127.0.0.1";
      port = config.ports.ollama-ui;
      environment = {
        SCARF_NO_ANALYTICS = "True";
        DO_NOT_TRACK = "True";
        ANONYMIZED_TELEMETRY = "False";
        OLLAMA_API_BASE_URL = "http://127.0.0.1:${toString config.ports.ollama-api}";
        WEBUI_AUTH = "False";
      };
    };
    traefik.dynamicConfigOptions.http = {
      routers = {
        ollama-frontend = {
          rule = "Host(`ollama.${config.networking.domain}`)";
          entryPoints = [ "https" ];
          service = "ollama-frontend";
        };
      };
      services = {
        ollama-frontend.loadBalancer = {
          passHostHeader = true;
          servers = [
            {
              url = "http://localhost:${toString config.ports.ollama-ui}";
            }
          ];
        };
      };
    };
  };
}
