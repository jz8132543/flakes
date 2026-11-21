{
  config,
  lib,
  osConfig ? { },
  pkgs,
  ...
}:
let
  cfg = lib.attrByPath [ "desktop" "voiceInput" ] { enable = false; } osConfig;
  enabled = cfg.enable;
  framework = lib.attrByPath [ "desktop" "inputMethod" "framework" ] "ibus" osConfig;
  models = "${cfg.package.models}/models/iic";
  json = pkgs.formats.json { };
in
lib.mkIf enabled {
  xdg.configFile."vocotype/config.json".source = json.generate "vocotype-offline.json" {
    asr = {
      native_enabled = true;
      model_dir = "${models}/speech_paraformer-large-contextual_asr_nat-zh-cn-16k-common-vocab8404-onnx";
      use_vad = true;
      vad_model_dir = "${models}/speech_fsmn_vad_zh-cn-16k-common-onnx";
      use_punc = true;
      punc_model_dir = "${models}/punc_ct-transformer_zh-cn-common-vocab272727-onnx";
      itn = true;
      intra_op_num_threads = cfg.threads;
      idle_timeout_s = 300;
    };
    asr_streaming = {
      enabled = cfg.streaming;
      model_dir = "${models}/speech_paraformer-large_asr_nat-zh-cn-16k-common-vocab8404-online-onnx";
      intra_op_num_threads = 1;
    };
    slm = {
      enabled = false;
      edit_enabled = false;
      endpoint = "";
      api_key = "";
    };
  };

  xdg.configFile."fcitx5/conf/vocotype.conf" = lib.mkIf (framework == "fcitx5") {
    text = ''
      PTTKey=F9
      PolishKey=Shift+F9
      EditKey=Control+F9
      PanelStyle=minimal
    '';
  };

  systemd.user.services.vocotype-fcitx5-backend = lib.mkIf (framework == "fcitx5") {
    Unit = {
      Description = "VoCoType Native Fcitx 5 Backend";
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${cfg.package}/bin/vocotype-fcitx5-backend --config ${
        config.xdg.configFile."vocotype/config.json".source
      }";
      PrivateNetwork = true;
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  xdg.configFile."vocotype/rime" = lib.mkIf (framework == "ibus") {
    source = osConfig.system.build.rimeUserData + "/share/rime-build";
    recursive = true;
  };

  home.activation.initializeVoCoTypeState = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    state=${lib.escapeShellArg "${config.xdg.configHome}/vocotype"}
    run mkdir -p "$state"
    if [ ! -e "$state/terms.yaml" ]; then
      run cp ${cfg.package}/share/vocotype/terms.yaml "$state/terms.yaml"
      run chmod u+w "$state/terms.yaml"
    fi
    ${lib.optionalString (framework == "ibus") ''
      run mkdir -p "$state/rime/build"
      for name in installation.yaml user.yaml; do
        if [ ! -e "$state/rime/$name" ] && [ ! -L "$state/rime/$name" ]; then
          run cp ${osConfig.system.build.rimeUserData}/share/rime-data/"$name" "$state/rime/$name"
          run chmod u+w "$state/rime/$name"
        fi
      done
      for source in ${osConfig.system.build.rimeUserData}/share/rime-data/build/*.yaml; do
        run cp --remove-destination "$source" "$state/rime/build/$(basename "$source")"
        run chmod u+w "$state/rime/build/$(basename "$source")"
      done
    ''}
  '';

  home.global-persistence.directories = [
    {
      directory = ".config/vocotype";
      mode = "0700";
    }
    {
      directory = ".local/share/vocotype";
      mode = "0700";
    }
  ];
}
