{ config, lib, ... }:
{
  options.services.local-llm.settings = {
    modelRoot = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/games/AI";
      description = "Mutable storage root for local model files and caches.";
    };

    strata = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Automatically prepare the configured Strata model on the model disk.";
      };

      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "${config.services.local-llm.settings.modelRoot}/strata";
        description = "Directory where Strata stores IQ3_XXS files and generated state.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = config.ports.strata;
        description = "Loopback API port used by the Strata managed runtime.";
      };

      family = lib.mkOption {
        type = lib.types.str;
        default = "qwen";
        description = "Strata model family passed to the preparation command.";
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "iq3_xxs";
        description = "Strata model identifier.";
      };

      context = lib.mkOption {
        type = lib.types.str;
        default = "8k";
        description = "Initial Strata context size.";
      };

      parallel = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1;
        description = "Initial Strata request parallelism.";
      };

      vision = lib.mkOption {
        type = lib.types.enum [
          "off"
          "on"
          "cpu"
          "gpu"
        ];
        default = "off";
        description = "Strata vision reader mode.";
      };

      access = lib.mkOption {
        type = lib.types.enum [
          "local"
          "lan"
        ];
        default = "local";
        description = "Strata network access mode.";
      };

    };

    duet = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Automatically download the configured DuET model into the model disk cache.";
      };

      modelDir = lib.mkOption {
        type = lib.types.str;
        default = "${config.services.local-llm.settings.modelRoot}/duet";
        description = "Mutable Hugging Face cache for DuET weights.";
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "Wayne42/DuET";
        description = "Hugging Face model repository used by DuET.";
      };
    };
  };
}
