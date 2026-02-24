{
  stdenv,
  source,
  lib,
}:
stdenv.mkDerivation {
  inherit (source) pname version src;

  phases = "installPhase";

  installPhase = ''
    tar xzf $src
    mkdir -p "$out/bin"
    install -m 755 realm -t "$out/bin/"
  '';

  meta = with lib; {
    description = "A simple, high performance relay server written in Rust";
    homepage = "https://github.com/zhboner/realm";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "realm";
  };
}
