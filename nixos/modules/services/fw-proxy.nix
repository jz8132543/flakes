{
  config,
  options,
  lib,
  ...
}: let
  cfg = config.networking.fw-proxy;
  inherit (config.networking) hostName;
  # profiles = ["main" "exclusive" "alternative"];
  profiles = ["main"];
in
  lib.mkMerge [
    {
      networking.fw-proxy = {
        enable = true;
        ports = {
          mixed = config.ports.proxy-mixed;
          tproxy = config.ports.proxy-tproxy;
          controller = config.ports.sing-box-controller;
        };
        noProxyPattern =
          options.networking.fw-proxy.noProxyPattern.default
          ++ lib.lists.forEach ([config.networking.domain] ++ config.environment.domains) (x: lib.strings.concatStrings ["*." x]);
        tproxy = {
          enable = lib.mkDefault true;
          routingTable = config.routingTables.fw-proxy;
          rulePriority = config.routingPolicyPriorities.fw-proxy;
        };
        downloadedConfigPreprocessing = ''
        '';
        configPreprocessing = ''
          jq 'del(.log) | del(.inbounds) | del(.experimental.clash_api)' "$raw_config" |\
            sponge "$raw_config"
          jq 'del(.outbounds[]|select(.tag=="auto")|.outbounds[]|select(.|test("3x","1.5x","0.8")))' "$raw_config" |
            sponge "$raw_config"
        '';
        mixinConfig = {
          log = {
            level = "info";
            timestamp = false; # added by journald
          };
        };
        profiles = lib.listToAttrs (lib.lists.map (p:
          lib.nameValuePair p {
            urlFile = config.sops.secrets."sing-box/${p}".path;
          })
        profiles);
        externalController = {
          expose = lib.mkDefault false;
          virtualHost = "${hostName}.*";
          location = "/sing-box/";
          secretFile = config.sops.secrets."fw_proxy_external_controller_secret".path;
        };
      };

      sops.secrets."fw_proxy_external_controller_secret" = {
        # terraformOutput.enable = true;
        restartUnits = ["sing-box-auto-update.service"];
      };

      networking.fw-proxy.auto-update = {
        enable = true;
        service = "main";
      };

      systemd.services.nix-daemon.environment = cfg.environment;
    }
    {
      sops.secrets = lib.listToAttrs (lib.lists.map (p:
        lib.nameValuePair "sing-box/${p}" {
          # sopsFile = config.sops-file.get "common.yaml";
          restartUnits = ["sing-box-auto-update.service"];
        })
      profiles);
    }
  ]
