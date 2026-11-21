{
  config,
  lib,
  pkgs,
  ...
}:
let
  aiModelsDir = "/mnt/games/AI";
  hf = lib.getExe pkgs.python3Packages.huggingface-hub;
  hfDownload = pkgs.writeShellScriptBin "hf-download" ''
    export HF_HOME=${lib.escapeShellArg aiModelsDir}
    export HF_HUB_CACHE=${lib.escapeShellArg aiModelsDir}
    export LLAMA_CACHE=${lib.escapeShellArg aiModelsDir}
    exec ${hf} download "$@"
  '';
in
{
  sops.secrets."open-webui/secret_key" = { };

  sops.templates."open-webui.env" = {
    mode = "0400";
    content = ''
      WEBUI_SECRET_KEY=${config.sops.placeholder."open-webui/secret_key"}
    '';
  };

  services.open-webui = {
    enable = lib.mkDefault true;
    host = "127.0.0.1";
    port = 8081;
    environmentFile = config.sops.templates."open-webui.env".path;
    environment = {
      ENABLE_OLLAMA_API = "False";
      OPENAI_API_BASE_URLS = "http://127.0.0.1:11437/v1,http://127.0.0.1:8080/v1";
      OPENAI_API_KEYS = "sk-local,sk-local";
      OFFLINE_MODE = "True";
      RAG_EMBEDDING_MODEL = "";
      RAG_EMBEDDING_MODEL_AUTO_UPDATE = "False";
      ANONYMIZED_TELEMETRY = "False";
      DO_NOT_TRACK = "True";
      SCARF_NO_ANALYTICS = "True";
    };
  };

  services.traefik.proxies.open-webui = {
    rule = "HostRegexp(`{host:.+}`)";
    target = "http://127.0.0.1:${toString config.services.open-webui.port}";
  };

  environment.systemPackages = [
    pkgs.llama-cpp
    pkgs.python3Packages.huggingface-hub
    hfDownload
  ];

  environment.sessionVariables = {
    HF_HOME = aiModelsDir;
    HF_HUB_CACHE = aiModelsDir;
    LLAMA_CACHE = aiModelsDir;
  };

  environment.variables = {
    HF_HOME = aiModelsDir;
    HF_HUB_CACHE = aiModelsDir;
    LLAMA_CACHE = aiModelsDir;
  };

  systemd.tmpfiles.rules = [
    "d ${aiModelsDir} 0755 tippy users -"
  ];
}
