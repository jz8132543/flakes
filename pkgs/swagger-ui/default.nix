{
  source,
  stdenv,
  unzip,
}:
stdenv.mkDerivation {
  inherit (source) pname version src;
  buildInputs = [unzip];
  dontUnpack = true;
  installPhase = ''
    mkdir -p $out
    unzip $src
    mv dist/* $out
  '';
}
