{
  stdenv,
  librime,
  rime-wanxiang-base,
  rime-wanxiang-gram,
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

  defaultCustomYaml = ''
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
  pname = "rime-deploy";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [ librime ];

  buildPhase = ''
        mkdir -p rime-data
        # 1. Copy base data (schemas, dicts from wanxiang)
        if [ -d "${rime-wanxiang-base}/share/fcitx5/rime" ]; then
          cp -rf ${rime-wanxiang-base}/share/fcitx5/rime/* rime-data/
        fi

        # 2. Copy grammar model
        if [ -f "${rime-wanxiang-gram}/share/fcitx5/rime/wanxiang-lts-zh-hans.gram" ]; then
          cp -f ${rime-wanxiang-gram}/share/fcitx5/rime/wanxiang-lts-zh-hans.gram rime-data/
        fi

        # 3. Copy user configuration from local directory
        cat > rime-data/default.custom.yaml <<'EOF'
    ${defaultCustomYaml}
    EOF

        if [ -f "$src/wanxiang.custom.yaml" ]; then
          cp -f "$src/wanxiang.custom.yaml" rime-data/wanxiang.custom.yaml
        fi

        if [ "${framework}" = "ibus" ]; then
          cat > rime-data/ibus_rime.custom.yaml <<'EOF'
    ${ibusCustomYaml}
    EOF
        fi

        # 4. Run Rime deployment to pre-compile schemas and dictionaries
        # rime_deployer --build <user_data_dir> [shared_data_dir]
        # We use the same directory for both to ensure all files are together
        rime_deployer --build rime-data rime-data
  '';

  installPhase = ''
    mkdir -p $out/share/rime-data
    cp -rf rime-data/* $out/share/rime-data/
  '';
}
