{
  lib,
  pkgs,
  config,
  ...
}:
let
  modelDir = config.services.local-llm.settings.strata.dataDir;
in
{
  config = {
    services.llama-swap = {
      enable = true;
      listenAddress = "0.0.0.0";
      port = 8080;
      settings = {
        healthCheckTimeout = 3600;
        models."llama-cpp" = {
          cmd = ''
            ${
              pkgs.llama-cpp.override { cudaSupport = true; }
            }/bin/llama-server --host 127.0.0.1 --port ''${PORT} --models-max 1 --parallel 1 --ctx-size 4096 --sleep-idle-seconds 600 --offline --no-webui
          '';
          checkEndpoint = "/health";
          ttl = 600;
        };
        routing.router.settings.groups.single = {
          swap = true;
          exclusive = true;
          members = [ "llama-cpp" ];
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
        IPAddressAllow = [
          "localhost"
          "100.64.0.0/10"
          "fd7a:115c:a1e0::/48"
        ];
      };
      environment = {
        HF_HOME = lib.mkForce modelDir;
        HF_HUB_CACHE = lib.mkForce modelDir;
        LLAMA_CACHE = lib.mkForce modelDir;
      };
    };
  };
}
