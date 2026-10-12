{
  options.services.llama-cpp = {
    enable = lib.mkEnableOption "Llama.cpp server";
    package = lib.mkOption {
      type = lib.types.package;
      description = "The Llama.cpp package to use. You can override it, e.g., enable CUDA support: pkgs.llama-cpp.override { cudaSupport = true; }";
    };
    settings = lib.mkOption {
      type = lib.types.submodule {
        options = {
          host = lib.mkOption {
            type = lib.types.str;
            default = "127.0.0.1";
            description = "IP address the server binds to (default 127.0.0.1). Use 0.0.0.0 to expose externally.";
          };
          port = lib.mkOption {
            type = lib.types.port;
            default = 8080;
            description = "TCP port for the Llama.cpp server.";
          };
          "models-dir" = lib.mkOption {
            type = lib.types.path;
            description = "Directory containing GGUF model files. The server can switch among any model present in this directory via the `model` query parameter.";
          };
          cache-dir = lib.mkOption {
            type = lib.types.path;
            default = "/var/cache/llama-cpp";
            description = "Directory used by llama.cpp for temporary caches (e.g., quantization cache, shader cache).";
          };
          n_threads = lib.mkOption {
            type = lib.types.int;
            default = 4;
            description = "Number of CPU threads the inference engine may use. Set to the number of physical cores for best performance.";
          };
          n_batch = lib.mkOption {
            type = lib.types.int;
            default = 512;
            description = "Maximum batch size passed to the backend. Larger values may improve throughput at the cost of latency.";
          };
        };
      };
      description = "Attributes mapped to `llama-server` command‑line flags. Any unsupported option is ignored.";
    };
    models = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Human‑readable identifier for the model (used in UI or scripts).";
            };
            path = lib.mkOption {
              type = lib.types.path;
              description = "Absolute path to the GGUF model file. Must reside under `settings.models-dir`.";
            };
            extraFlags = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Additional `--<flag>` arguments specific to this model (e.g., \"--prompt-cache-dir /var/cache/prompt\").";
            };
          };
        }
      );
      default = [ ];
      description = "A list of model descriptors that can be referenced by a wrapper script or API layer to launch the server with a particular model without moving files around.";
    };
  };

  config = lib.mkIf config.services.llama-cpp.enable {
    systemd.services.llama-cpp = {
      description = "Llama.cpp inference server";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart =
          "${config.services.llama-cpp.package}/bin/llama-server "
          + "--host ${config.services.llama-cpp.settings.host} "
          + "--port ${toString config.services.llama-cpp.settings.port} "
          + "--models-dir ${config.services.llama-cpp.settings.models-dir} "
          + "--cache-dir ${config.services.llama-cpp.settings.cache-dir} "
          + "--n-threads ${toString config.services.llama-cpp.settings.n_threads} "
          + "--n-batch ${toString config.services.llama-cpp.settings.n_batch}";
        User = "dynamic";
        DynamicUser = true;
        ReadOnlyPaths = [ config.services.llama-cpp.settings.models-dir ];
        Environment = "HF_HOME=${config.services.llama-cpp.settings.models-dir}";
      };
    };
  };
}
