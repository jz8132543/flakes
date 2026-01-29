{ pkgs, source, ... }:
pkgs.stdenv.mkDerivation {
  pname = "jellyfin-plugin-reports";
  inherit (source) version;
  inherit (source) src;

  nativeBuildInputs = [ pkgs.unzip ];
  sourceRoot = ".";

  installPhase = ''
    mkdir -p $out
    cp -r * $out/
  '';
}
