{ pkgs, source, ... }:
pkgs.stdenv.mkDerivation {
  pname = "jellyfin-plugin-intro-skipper";
  inherit (source) version;
  inherit (source) src;

  nativeBuildInputs = [ pkgs.unzip ];
  sourceRoot = ".";

  installPhase = ''
    mkdir -p $out
    cp -r * $out/
  '';
}
