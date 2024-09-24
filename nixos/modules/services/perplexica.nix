{ config, ... }:
{
  virtualisation.oci-containers.containers = {
    perplexica-backend = {
      image = "elestio4test/perplexica-backend";
      autoStart = true;
      volumes = [
        "${config.sops.templates.perplexica.path}:/home/perplexica/config.toml"
      ];
      ports = [ "127.0.0.1:${toString config.ports.perplexica-backend}:3001" ];
    };
    perplexica-frontend = {
      image = "elestio4test/perplexica-frontend";
      autoStart = true;
      labels = {
        NEXT_PUBLIC_API_URL = "http://127.0.0.1:${toString config.ports.perplexica-backend}/api";
        NEXT_PUBLIC_WS_URL = "ws://127.0.0.1:${toString config.ports.perplexica-backend}";
      };
      ports = [ "127.0.0.1:${toString config.ports.perplexica-frontend}:3000" ];
    };
  };
  sops.templates.perplexica = {
    # owner = "acme";
    content = ''
      [GENERAL]
      PORT = 3001 # Port to run the server on
      SIMILARITY_MEASURE = "cosine" # "cosine" or "dot"

      [API_KEYS]
      OPENAI = "" # OpenAI API key - sk-1234567890abcdef1234567890abcdef
      GROQ = "" # Groq API key - gsk_1234567890abcdef1234567890abcdef
      ANTHROPIC = "" # Anthropic API key - sk-ant-1234567890abcdef1234567890abcdef

      [API_ENDPOINTS]
      SEARXNG = "${config.services.searx.settings.server.base_url}" # SearxNG API URL
      OLLAMA = "" # Ollama API URL - http://host.docker.internal:11434
    '';
  };
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      perplexica = {
        rule = "Host(`p.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "perplexica";
      };
    };
    services = {
      perplexica.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.perplexica-frontend}"; } ];
      };
    };
  };
}
