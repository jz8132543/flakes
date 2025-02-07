{ config, ... }:
{
  services = {
    ollama = {
      enable = true;
      loadModels = [ "deepseek-r1:7B" ];
    };
    open-webui = {
      enable = true;
      host = "127.0.0.1";
    };
    traefik.dynamicConfigOptions.http = {
      routers = {
        perplexica-frontend = {
          rule = "Host(`p.${config.networking.domain}`)";
          entryPoints = [ "https" ];
          service = "perplexica-frontend";
        };
        perplexica-backend = {
          rule = "Host(`perplexica-backend.${config.networking.domain}`)";
          entryPoints = [ "https" ];
          service = "perplexica-backend";
        };
      };
      services = {
        perplexica-frontend.loadBalancer = {
          passHostHeader = true;
          servers = [
            {
              url = "http://localhost:${toString config.ports.perplexica-frontend}";
            }
          ];
        };
        perplexica-backend.loadBalancer = {
          passHostHeader = true;
          servers = [
            {
              url = "http://localhost:${toString config.ports.perplexica-backend}";
            }
          ];
        };
      };
    };
  };
}
