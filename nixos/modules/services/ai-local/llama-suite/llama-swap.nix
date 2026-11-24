{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.services.local-llm.settings;
  modelDir = cfg.strata.dataDir;
  strataHome = "${modelDir}/xdg-data/strata";
  strata = pkgs.nur.repos.xddxdd.strata;
  strataExe = lib.getExe strata;
  setupArgs = [
    "--family"
    cfg.strata.family
    "--model"
    cfg.strata.model
    "--context"
    cfg.strata.context
    "--vision"
    cfg.strata.vision
    "--parallel"
    (toString cfg.strata.parallel)
    "--data-dir"
    cfg.strata.dataDir
    "--low-ram"
    cfg.strata.lowRam
    "--source"
    cfg.strata.source
    "--port"
    (toString cfg.strata.port)
    "--yes"
    "--setup"
    "--no-start"
    "--no-browser"
  ];
  runScript = "${strataHome}/run-${lib.toLower cfg.strata.model}.sh";
  downloadProxyEnv = lib.optionalAttrs (cfg.strata.downloadProxy != null) {
    HTTPS_PROXY = cfg.strata.downloadProxy;
    HTTP_PROXY = cfg.strata.downloadProxy;
    ALL_PROXY = cfg.strata.downloadProxy;
  };
in
{
  config = {
    services.traefik.proxies.strata = lib.mkIf cfg.strata.enable {
      rule = "Host(`strata.${config.networking.domain}`)";
      target = "http://127.0.0.1:${toString cfg.strata.port}";
      middlewares = [ "auth" ];
      homepage = {
        title = "Strata";
        category = "AI";
        icon = "si-ollama";
        description = "Local Strata inference UI and API";
        href = "http://127.0.0.1:${toString cfg.strata.port}";
      };
    };

    systemd.services.strata-model-prepare = lib.mkIf cfg.strata.enable {
      description = "Prepare Strata ${cfg.strata.model} model files";
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
        mkdir -p ${lib.escapeShellArg "${modelDir}/xdg-data"}
        ${strataExe} ${lib.escapeShellArgs setupArgs}
        test -x ${lib.escapeShellArg runScript}
      '';
    };

    systemd.services.strata = lib.mkIf cfg.strata.enable {
      description = "Strata ${cfg.strata.model} OpenAI-compatible API";
      path = [ config.hardware.nvidia.package ];
      after = [ "strata-model-prepare.service" ];
      requires = [ "strata-model-prepare.service" ];
      wants = [ "network-online.target" ];
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
        IPAddressAllow = "localhost";
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

    services.llama-swap = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 8080;
      settings = {
        healthCheckTimeout = 3600;
        models = {
          "llama-cpp" = {
            cmd = ''
              ${
                pkgs.llama-cpp.override { cudaSupport = true; }
              }/bin/llama-server --host 127.0.0.1 --port ''${PORT} --models-max 1 --parallel 1 --ctx-size 4096 --sleep-idle-seconds 600 --offline --no-webui
            '';
            checkEndpoint = "/health";
            ttl = 600;
          };
        };
        routing.router.settings.groups.single = {
          swap = true;
          exclusive = true;
          members = [
            "llama-cpp"
          ];
        };
      };
    };

    services.homepage-dashboard.services = [
      {
        AI = [
          {
            llama-swap = {
              href = "http://127.0.0.1:8080";
              icon = "si-ollama";
              description = "Local model routing and playground";
            };
          }
        ];
      }
    ];

    systemd.services.llama-swap = {
      unitConfig.RequiresMountsFor = modelDir;
      serviceConfig = {
        User = "tippy";
        Group = "users";
        DynamicUser = lib.mkForce false;
        SupplementaryGroups = [
          "video"
          "render"
        ];
        ReadWritePaths = [
          modelDir
          "/home/tippy/.cache"
        ];
        IPAddressDeny = "any";
        IPAddressAllow = "localhost";
      };
      environment = {
        HF_HOME = lib.mkForce modelDir;
        HF_HUB_CACHE = lib.mkForce modelDir;
        LLAMA_CACHE = lib.mkForce modelDir;
      };
    };

    environment.systemPackages = [ strata ];
    systemd.tmpfiles.rules = [ "d ${modelDir} 0750 tippy users -" ];
  };
}
