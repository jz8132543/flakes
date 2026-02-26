{
  stdenv,
  source,
}:

stdenv.mkDerivation rec {
  pname = "rime-wanxiang-gram";
  version = "LTS";

  inherit (source) src;

  dontBuild = true;
  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/share/fcitx5/rime
    cp $src $out/share/fcitx5/rime/wanxiang-lts-zh-hans.gram
  '';
}
