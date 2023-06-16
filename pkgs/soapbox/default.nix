{
  source,
  stdenv,
  lib,
  unzip,
}:
stdenv.mkDerivation {
  inherit (source) pname version src;
  buildInputs = [unzip];
  dontUnpack = true;
  installPhase = ''
    # mkdir -p $out/frontends/soapbox/stable
    # unzip $src
    # mv static/* $out/frontends/soapbox/stable
    mkdir -p $out
    unzip $src
    mv static/* $out
  '';
  meta = with lib; {
    description = "zhwiki dictionary for fcitx5-pinyin and rime";
    homepage = "https://github.com/felixonmars/fcitx5-pinyin-zhwiki";
    license = licenses.unlicense;
  };
}
