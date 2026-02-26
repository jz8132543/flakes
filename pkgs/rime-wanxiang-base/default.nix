{
  stdenv,
  source,
  unzip,
}:

stdenv.mkDerivation rec {
  pname = "rime-wanxiang-base";
  version = "LTS";

  inherit (source) src;

  nativeBuildInputs = [ unzip ];

  unpackPhase = ''
    unzip ${src} -d $PWD
  '';

  installPhase = ''
    mkdir -p $out/share/fcitx5/rime
    cp -r $PWD/* $out/share/fcitx5/rime/
  '';
}
