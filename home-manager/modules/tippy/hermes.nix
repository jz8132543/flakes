{
  inputs,
  pkgs,
  ...
}:
{
  imports = [ inputs.hermes-agent.homeManagerModules.default ];

  programs.hermes-agent = {
    enable = true;
    package = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };

  services.hermes-agent = {
    enable = true;
    gateway.enable = true;
    hermesHome = "/home/tippy/.hermes";
    workingDirectory = "/home/tippy";
    settings = {
      model = {
        provider = "local-llama";
        default = "llama-cpp";
      };
      terminal.backend = "local";
      tools.exec.confirmation = "always";
      providers.local-llama = {
        api = "http://127.0.0.1:8080/v1";
        key_env = "HERMES_LOCAL_API_KEY";
        models = [ "llama-cpp" ];
      };
      providers.new-api = {
        name = "New-API";
        api = "https://api.dora.im/v1";
        key_env = "OPENAI_API_KEY";
        models = [ ];
        discover_models = true;
      };
    };
    environmentFiles = [ "/run/secrets/rendered/hermes-provider.env" ];
    environment.HERMES_LOCAL_API_KEY = "local";
  };

  home.global-persistence.directories = [ ".hermes" ];
}
