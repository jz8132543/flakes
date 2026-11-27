{
  nixosModules,
  ...
}:
let
  strataConfig =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.local-llm.settings.strata;
      modelDir = cfg.dataDir;
      strataHome = "${modelDir}/xdg-data/strata";
      strata = pkgs.nur.repos.xddxdd.strata;
      runScript = "${strataHome}/run-${lib.toLower cfg.model}.sh";
      runConfig = "${strataHome}/strata-${lib.toLower cfg.model}.json";
      server = "${strataHome}/serve/server.py";
      setupArgs = [
        "--family"
        cfg.family
        "--model"
        cfg.model
        "--context"
        cfg.context
        "--vision"
        cfg.vision
        "--parallel"
        (toString cfg.parallel)
        "--data-dir"
        cfg.dataDir
        "--low-ram"
        cfg.lowRam
        "--source"
        cfg.source
        "--port"
        (toString cfg.port)
        "--yes"
        "--setup"
        "--no-start"
        "--no-browser"
      ];
      downloadProxyEnv = lib.optionalAttrs (cfg.downloadProxy != null) {
        HTTPS_PROXY = cfg.downloadProxy;
        HTTP_PROXY = cfg.downloadProxy;
        ALL_PROXY = cfg.downloadProxy;
      };
      ompModels = pkgs.writeText "omp-strata-models.yml" ''
        providers:
          strata:
            baseUrl: http://127.0.0.1:${toString cfg.port}/v1
            api: openai-completions
            auth: none
            discovery:
              type: openai-models-list
              timeoutMs: 300000
            modelOverrides:
              qwen3.8-flash-next-iq3_xxs:
                contextWindow: 32768
                maxTokens: 8192
      '';
      modelId = "strata/qwen3.8-flash-next-iq3_xxs";
      ompConfig = pkgs.writeText "omp-strata-config.yml" ''
        modelRoles:
          default: ${modelId}
      '';
    in
    {
      services.traefik.proxies.strata = lib.mkIf cfg.enable {
        rule = "Host(`strata.${config.networking.domain}`)";
        target = "http://127.0.0.1:${toString cfg.port}";
        middlewares = [ "auth" ];
        homepage = {
          title = "Strata";
          category = "AI";
          icon = "si-ollama";
          description = "Local Strata inference UI and API";
          href = "http://${config.networking.hostName}.ts:${toString cfg.port}";
        };
      };

      systemd.services.strata-model-prepare = lib.mkIf cfg.enable {
        description = "Prepare Strata ${cfg.model} model files";
        path = [ config.hardware.nvidia.package ];
        wants = [
          "network-online.target"
          "mihomo.service"
        ];
        after = [
          "network-online.target"
          "mihomo.service"
        ];
        unitConfig.RequiresMountsFor = modelDir;
        serviceConfig = {
          Type = "oneshot";
          User = "tippy";
          Group = "users";
          RemainAfterExit = true;
          TimeoutStartSec = "infinity";
          SupplementaryGroups = [
            "video"
            "render"
          ];
          ReadWritePaths = [ modelDir ];
        };
        environment = {
          XDG_DATA_HOME = "${modelDir}/xdg-data";
          XDG_CONFIG_HOME = "${modelDir}/xdg-config";
          XDG_STATE_HOME = "${modelDir}/xdg-state";
          HF_ENDPOINT = "https://huggingface.co";
          NO_PROXY = "localhost,127.0.0.1,::1";
        }
        // downloadProxyEnv;
        script = ''
          set -eu
          if ! test -x ${lib.escapeShellArg runScript}; then
            mkdir -p ${lib.escapeShellArg "${modelDir}/xdg-data"}
            ${lib.getExe strata} ${lib.escapeShellArgs setupArgs}
          fi
          test -x ${lib.escapeShellArg runScript}
          test -f ${lib.escapeShellArg runConfig}
          test -f ${lib.escapeShellArg server}
        '';
      };

      systemd.services.strata = lib.mkIf cfg.enable {
        description = "Strata ${cfg.model} lazy OpenAI-compatible API";
        path = [ config.hardware.nvidia.package ];
        preStart = ''
          ${pkgs.python3}/bin/python3 - ${lib.escapeShellArg runConfig} <<'PY'
          import json
          import os
          import tempfile
          from pathlib import Path

          path = Path(os.sys.argv[1])
          raw = path.read_text()
          if raw.endswith(chr(92) + "n"):
              raw = raw[:-2]
          config = json.loads(raw)
          config.update({"lazy_load": True, "idle_unload_s": 600, "host": "0.0.0.0"})
          allowed_hosts = config.get("allowed_hosts", [])
          if isinstance(allowed_hosts, str):
              allowed_hosts = [allowed_hosts]
          config["allowed_hosts"] = list(dict.fromkeys([*allowed_hosts, "${config.networking.hostName}.ts"]))
          args = config["args"]
          for index, value in enumerate(args[:-1]):
              if value == "--max-context":
                  args[index + 1] = "32768"
                  break
          else:
              raise SystemExit("Strata config is missing --max-context")
          config["args_written"] = args.copy()
          fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".")
          try:
              with os.fdopen(fd, "w") as stream:
                  json.dump(config, stream, indent=2)
                  stream.write("\n")
                  stream.flush()
                  os.fsync(stream.fileno())
              os.replace(temporary, path)
          finally:
              if os.path.exists(temporary):
                  os.unlink(temporary)
          PY
        '';
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [
          "network-online.target"
          "strata-model-prepare.service"
        ];
        requires = [ "strata-model-prepare.service" ];
        unitConfig.RequiresMountsFor = modelDir;
        serviceConfig = {
          Type = "simple";
          User = "tippy";
          Group = "users";
          SupplementaryGroups = [
            "video"
            "render"
          ];
          TimeoutStartSec = "infinity";
          ReadWritePaths = [ modelDir ];
          IPAddressDeny = "any";
          IPAddressAllow = [
            "localhost"
            "100.64.0.0/10"
            "fd7a:115c:a1e0::/48"
          ];
        };
        environment = {
          XDG_DATA_HOME = "${modelDir}/xdg-data";
          XDG_CONFIG_HOME = "${modelDir}/xdg-config";
          XDG_STATE_HOME = "${modelDir}/xdg-state";
        };
        script = ''
          test -x ${lib.escapeShellArg runScript}
          exec ${lib.escapeShellArg runScript}
        '';
      };

      home-manager.users.tippy.home.file.".omp/agent/models.yml".source = ompModels;
      home-manager.users.tippy.home.file.".omp/agent/config.yml".source = ompConfig;
      services.paseo.settings.agents.providers.omp.additionalModels = [
        {
          id = modelId;
          label = "Qwen3.8 Flash Next IQ3_XXS (Strata)";
          isDefault = true;
        }
      ];

      environment.systemPackages = [ strata ];
      systemd.tmpfiles.rules = [ "d ${modelDir} 0750 tippy users -" ];
    };
in
{
  nix.settings = {
    extra-substituters = [ "https://cache.lantian.pub/lantian" ];
    extra-trusted-public-keys = [
      "lantian:WVGO7vsRMSEN+h7Lp7kv6SAmrkEXgUGbbXm7jMDjBuQ="
    ];
  };

  imports = [
    nixosModules.services.ai-local.settings
    nixosModules.services.ai-local."llama-suite".llama-cpp
    nixosModules.services.ai-local."llama-suite".llama-swap
    strataConfig
  ];
}
