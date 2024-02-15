{
  source,
  stdenv,
}:
stdenv.mkDerivation {
  inherit (source) pname version src;
  installPhase = ''
    mkdir -p $out
    mv nixos/mainframe/chisato.jpg $out/wallpaper.jpg
  '';
}
