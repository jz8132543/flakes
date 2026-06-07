{
  fetchurl,
  stdenv,
  ...
}:
let
  version = "LTS";
  src = fetchurl {
    url = "https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram";
    sha256 = "sha256-kXLnfXgeqe8C7z26qAQm5ihKzGbySmkuT+iQAT16d7c=";
  };
in
stdenv.mkDerivation rec {
  pname = "rime-wanxiang-gram";
  inherit version src;

  dontBuild = true;
  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/share/fcitx5/rime
    cp $src $out/share/fcitx5/rime/wanxiang-lts-zh-hans.gram
  '';
}
