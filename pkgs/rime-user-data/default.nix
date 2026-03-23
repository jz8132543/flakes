{
  stdenv,
  librime,
  rime-deploy,
  framework ? "ibus",
  terminalEnglishApps ? [
    "kitty"
    "Alacritty"
    "alacritty"
    "foot"
    "neovide"
    "org.wezfurlong.wezterm"
    "org.gnome.Console"
    "gnome-terminal-server"
    "com.raggesilver.BlackBox"
  ],
  ...
}:

let
  renderAppOptions =
    apps:
    builtins.concatStringsSep "\n" (builtins.map (app: "    \"${app}\":\n      ascii_mode: true") apps);

  customYaml = ''
    patch:
      schema_list:
        - schema: wanxiang
      ascii_composer:
        good_old_caps_lock: true
        switch_key:
          Shift_L: noop
          Shift_R: noop
      app_options:
    ${renderAppOptions terminalEnglishApps}
  '';

  ibusCustomYaml = ''
    patch:
      style:
        horizontal: true
        inline_preedit: true
        preedit_style: composition
  '';
in
stdenv.mkDerivation {
  pname = "rime-user-data-${framework}";
  version = "1.0.0";

  nativeBuildInputs = [ librime ];

  dontUnpack = true;

  buildPhase = ''
        runHook preBuild

        mkdir -p rime-data
        cp -r ${rime-deploy}/share/rime-data/. rime-data/
        chmod -R u+w rime-data

        cat > rime-data/default.custom.yaml <<'EOF'
    ${customYaml}
    EOF

        cp -f ${../rime-deploy/wanxiang.custom.yaml} rime-data/wanxiang.custom.yaml

        if [ "${framework}" = "ibus" ]; then
          cat > rime-data/ibus_rime.custom.yaml <<'EOF'
    ${ibusCustomYaml}
    EOF
        fi

        rime_deployer --build rime-data rime-data

        runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/rime-data
    cp -r rime-data/. $out/share/rime-data/

    runHook postInstall
  '';
}
