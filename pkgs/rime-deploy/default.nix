{
  pkgs,
  stdenv,
  lib,
  fetchurl,
  librime,
  rime-wanxiang,
  rimeData ? pkgs.rime-data,
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
  wanxiangGram = fetchurl {
    url = "https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram";
    sha256 = "sha256-kXLnfXgeqe8C7z26qAQm5ihKzGbySmkuT+iQAT16d7c=";
  };

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
        set -euxo pipefail

        mkdir -p rime-data shared-data build deployed-data

        # 1. Copy the base Rime presets needed by rime_deployer.
        if [ -d "${rimeData}/share/rime-data" ]; then
          cp -rf ${rimeData}/share/rime-data/* shared-data/
        fi

        # 2. Copy wanxiang schemas and dictionaries.
        if [ -d "${rime-wanxiang}/share/rime-data" ]; then
          cp -rf ${rime-wanxiang}/share/rime-data/* shared-data/
        fi

        # 3. Copy grammar model.
        cp -f ${wanxiangGram} shared-data/wanxiang-lts-zh-hans.gram

        # 4. Copy user configuration from local directory.
        cat > rime-data/default.yaml <<'EOF'
      schema_list:
        - schema: wanxiang
    EOF

        cp -f ${./default.custom.yaml} rime-data/default.custom.yaml
        cp -f ${./wanxiang.custom.yaml} rime-data/wanxiang.custom.yaml
        chmod u+w rime-data/default.custom.yaml rime-data/wanxiang.custom.yaml

        for app in ${lib.escapeShellArgs terminalEnglishApps}; do
          if ! grep -Eq "^    \"?$app\"?:" rime-data/default.custom.yaml; then
            printf '    "%s":\n      ascii_mode: true\n' "$app" >> rime-data/default.custom.yaml
          fi
        done

        if [ "${framework}" = "ibus" ]; then
          cat > rime-data/ibus_rime.custom.yaml <<'EOF'
    ${ibusCustomYaml}
    EOF
        fi

        # These files make the generated tree look like an already initialized
        # user data directory, so ibus-rime does not ask to deploy on first run.
        cat > rime-data/installation.yaml <<'EOF'
    distribution_code_name: ibus-rime
    distribution_name: ibus-rime
    installation_id: nixos-rime-deploy
    sync_dir: sync
    EOF

        cat > rime-data/user.yaml <<'EOF'
    var:
      previously_selected_schema: wanxiang
      schema_access_time:
        wanxiang: 1
    EOF

        ${librime}/bin/rime_deployer --build rime-data shared-data build

        cp -rf shared-data/. deployed-data/
        cp -rf rime-data/. deployed-data/
        mkdir -p deployed-data/build
        cp -rf build/. deployed-data/build/
  '';

  installPhase = ''
    mkdir -p $out/share/rime-data
    mkdir -p $out/share/rime-build
    cp -rf shared-data/. $out/share/rime-data/
    cp -rf rime-data/. $out/share/rime-data/
    cp -rf deployed-data/. $out/share/rime-build/
  '';
}
