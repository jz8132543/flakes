{
  source,
  stdenv,
}:
stdenv.mkDerivation {
  inherit (source) pname version src;
  unpackPhase = ":";
  installPhase = ''
    # mkdir -p $out
    # install -m 444 $src $out/trackerslist.txt
    install -m 444 $src $out
  '';
}
