{
  source,
  stdenv,
}:
stdenv.mkDerivation {
  inherit (source) pname version src;
  installPhase = ''
    mkdir -p $out
    mv themes/* $out
  '';
}
