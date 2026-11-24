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
    port = config.ports.open-webui;
    environmentFile = config.sops.templates."open-webui.env".path;
    environment = {
      ENABLE_OLLAMA_API = "False";
      ENABLE_OPENAI_API = "True";
      # Open WebUI separates provider URLs and keys with semicolons, not commas.
      OPENAI_API_BASE_URLS = "http://127.0.0.1:${toString config.ports.strata}/v1;http://127.0.0.1:${toString config.services.llama-swap.port}/v1";
      OPENAI_API_KEYS = "sk-local;sk-local";
      OPENAI_API_CONFIGS = "{}";
      OFFLINE_MODE = "True";
      RAG_EMBEDDING_MODEL = "";
      RAG_EMBEDDING_MODEL_AUTO_UPDATE = "False";
      ANONYMIZED_TELEMETRY = "False";
      DO_NOT_TRACK = "True";
      SCARF_NO_ANALYTICS = "True";
    };
  };

  # Persistent provider settings override environment defaults in Open WebUI.
  # Synchronize only the local OpenAI connections, without resetting other state.
  systemd.services.open-webui.preStart = lib.mkBefore ''
    ${pkgs.python3}/bin/python3 - <<'PY'
    import json
    import os
    import sqlite3
    from pathlib import Path

    database = Path(os.environ["DATA_DIR"]) / "webui.db"
    if database.is_file():
        settings = {
            "openai.enable": os.environ["ENABLE_OPENAI_API"].lower() == "true",
            "openai.api_base_urls": os.environ["OPENAI_API_BASE_URLS"].split(";"),
            "openai.api_keys": os.environ["OPENAI_API_KEYS"].split(";"),
            "openai.api_configs": json.loads(os.environ["OPENAI_API_CONFIGS"]),
        }
        with sqlite3.connect(database, timeout=30) as connection:
            connection.executemany(
                "INSERT INTO config (key, value, updated_at) VALUES (?, ?, unixepoch()) "
                "ON CONFLICT(key) DO UPDATE SET value = excluded.value, "
                "updated_at = excluded.updated_at WHERE config.value != excluded.value",
                [(key, json.dumps(value)) for key, value in settings.items()],
            )
    PY
  '';

  services.traefik.proxies.open-webui = {
    rule = "Host(`open-webui.${config.networking.domain}`)";
    target = "http://127.0.0.1:${toString config.services.open-webui.port}";
    homepage = {
      title = "Open WebUI";
      category = "AI";
      icon = "open-webui.png";
      description = "Local AI models";
      href = "http://127.0.0.1:${toString config.services.open-webui.port}";
    };
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
