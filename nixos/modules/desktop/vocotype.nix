{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.voiceInput;
  framework = config.desktop.inputMethod.framework;
  # The unmodified IBus engine searches /usr/share/rime-data. Give only this
  # process an FHS view; do not create global /usr paths or patch its sources.
  ibusEnvironment = pkgs.buildFHSEnv {
    name = "vocotype-ibus-env";
    targetPkgs = _: [ config.system.build.rimeUserData ];
    runScript = "${cfg.package}/libexec/vocotype-ibus-engine";
    unshareNet = true;
  };
  ibusEngine =
    pkgs.runCommand "vocotype-ibus-component"
      {
        meta.isIbusEngine = true;
        passthru = { inherit ibusEnvironment; };
      }
      ''
        mkdir -p "$out/share/ibus/component"
        substitute ${cfg.package}/share/ibus/component/vocotype.xml \
          "$out/share/ibus/component/vocotype.xml" \
          --replace-fail '${cfg.package}/libexec/vocotype-ibus-engine' \
            '${ibusEnvironment}/bin/vocotype-ibus-env'
      '';
in
{
  options.desktop.voiceInput = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable local CPU speech input with the selected input method framework.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.vocotype;
      description = "VoCoType with native Fcitx 5/IBus frontends and CPU-only inference.";
    };
    threads = lib.mkOption {
      type = lib.types.ints.between 1 8;
      default = 4;
      description = "CPU threads for final offline speech recognition.";
    };
    streaming = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show local streaming speech previews before final recognition and submission.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    system.extraDependencies = [ cfg.package.models ];
    i18n.inputMethod.fcitx5.addons = lib.mkIf (framework == "fcitx5") [ cfg.package ];
    i18n.inputMethod.ibus.engines = lib.mkIf (framework == "ibus") [ ibusEngine ];
  };
}
