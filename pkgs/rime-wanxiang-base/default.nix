{
  fetchurl,
  stdenv,
  unzip,
  ...
}:
let
  version = "LTS";
  src = fetchurl {
    url = "https://github.com/amzxyz/rime_wanxiang/releases/download/v15.12.3/rime-wanxiang-base.zip";
    sha256 = "sha256-DvYKwWgKDQUYRDPyuYJw6mhyvsmojlB9EdEUYzTp30A=";
  };
in
stdenv.mkDerivation rec {
  pname = "rime-wanxiang-base";
  inherit version src;

  nativeBuildInputs = [ unzip ];

  unpackPhase = ''
    unzip ${src} -d $PWD
  '';

  installPhase = ''
    mkdir -p $out/share/fcitx5/rime
    cp -r $PWD/* $out/share/fcitx5/rime/
  '';
}
