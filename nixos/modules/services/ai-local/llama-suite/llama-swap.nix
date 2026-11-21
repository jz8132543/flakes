{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.services.local-llm.settings;
  modelDir = cfg.strata.dataDir;
  strata = pkgs.nur.repos.xddxdd.strata;
  strataExe = lib.getExe strata;
  strataProfile = "arx8-iq3-xxs";
  launchArgs = [
    "launch"
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
    "--access"
    cfg.strata.access
    "--port"
    (toString cfg.strata.port)
    "--save-preset"
    strataProfile
    "--yes"
    "--no-tui"
  ];
in
{
  config = {
    systemd.services.strata-model-prepare = lib.mkIf cfg.strata.enable {
      description = "Prepare Strata ${cfg.strata.model} model files";
      wantedBy = [ "multi-user.target" ];
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
      };
      script = ''
        set -eu
        mkdir -p ${lib.escapeShellArg modelDir}
        ${strataExe} launch ${lib.escapeShellArgs launchArgs} --plan
      '';
    };

    systemd.services.strata = lib.mkIf cfg.strata.enable {
      description = "Strata ${cfg.strata.model} OpenAI-compatible API";
      wantedBy = [ "multi-user.target" ];
      after = [ "strata-model-prepare.service" ];
      requires = [ "strata-model-prepare.service" ];
      unitConfig.RequiresMountsFor = modelDir;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
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
        exec ${strataExe} ${lib.escapeShellArgs launchArgs}
      '';
      preStop = ''
        ${strataExe} launch --stop --preset ${lib.escapeShellArg strataProfile}
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
  };
}
