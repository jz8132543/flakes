{
  stdenv,
  librime,
  rime-wanxiang-base,
  rime-wanxiang-gram,
}:
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
    cp -vf *.yaml rime-data/

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

