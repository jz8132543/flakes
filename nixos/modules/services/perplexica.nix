{
  config,
  nixosModules,
  ...
}:
{
  imports = [
    nixosModules.services.podman
  ];
  virtualisation.oci-containers.containers = {
    perplexica-backend = {
      hostname = "perplexica-backend";
      image = "hajowieland/perplexica-backend";
      autoStart = true;
      volumes = [
        "${config.sops.templates.perplexica.path}:/home/perplexica/config.toml"
      ];
      ports = [ "127.0.0.1:${toString config.ports.perplexica-backend}:3001" ];
    };
    perplexica-frontend = {
      hostname = "perplexica-backend";
      image = "hajowieland/perplexica-frontend";
      autoStart = true;
      environment = {
        NEXT_PUBLIC_API_URL = "https://perplexica-backend.${config.networking.domain}/api";
        NEXT_PUBLIC_WS_URL = "wss://perplexica-backend.${config.networking.domain}";
      };
      cmd = [
        "/bin/sh"
        "-c"
        "yarn build; yarn start"
      ];
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
      OLLAMA = "https://ollama.${config.networking.domain}" # Ollama API URL - http://host.docker.internal:11434
    '';
  };
  services.traefik.dynamicConfigOptions.http = {
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
        servers = [ { url = "http://localhost:${toString config.ports.perplexica-frontend}"; } ];
      };
      perplexica-backend.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.perplexica-backend}"; } ];
      };
    };
  };
}
