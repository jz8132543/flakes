{
  config,
  lib,
  nixosModules,
  pkgs,
  ...
}:
let
  cfg = config.services.duet;
  settings = config.services.local-llm.settings.duet;
in
{
  imports = [ nixosModules.services.ai-local.settings ];
  options.services.duet = {
    enable = lib.mkEnableOption "DuET piano performance-to-score transcription";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.duet;
      description = "DuET CLI package.";
    };
    modelDir = lib.mkOption {
      type = lib.types.str;
      default = settings.modelDir;
      description = "Mutable Hugging Face cache for DuET weights.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    systemd.tmpfiles.rules = [ "d ${cfg.modelDir} 0750 tippy users -" ];
    systemd.services.duet-model-prepare = lib.mkIf settings.enable {
      description = "Prepare DuET model weights";
      wantedBy = [ "multi-user.target" ];
      unitConfig.RequiresMountsFor = cfg.modelDir;
      serviceConfig = {
        Type = "oneshot";
        User = "tippy";
        Group = "users";
        RemainAfterExit = true;
        TimeoutStartSec = "30m";
        ReadWritePaths = [ cfg.modelDir ];
      };
      environment = {
        HF_HOME = "${cfg.modelDir}/huggingface";
        HF_HUB_CACHE = "${cfg.modelDir}/huggingface";
      };
      script = ''
        set -eu
        mkdir -p ${lib.escapeShellArg cfg.modelDir}
        marker=${lib.escapeShellArg cfg.modelDir}/.model-ready
        if [ -s "$marker" ]; then
          exit 0
        fi
        ${cfg.package}/bin/duet-prepare ${lib.escapeShellArg settings.model}
        touch "$marker"
      '';
    };
    systemd.services.duet.environment = {
      HF_HOME = "${cfg.modelDir}/huggingface";
      HF_HUB_CACHE = "${cfg.modelDir}/huggingface";
    };
  };
}
