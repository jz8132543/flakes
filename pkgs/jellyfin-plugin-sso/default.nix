{
  pkgs,
  source,
  ...
}:
pkgs.stdenv.mkDerivation {
  pname = "jellyfin-plugin-sso";
  inherit (source) version;
  inherit (source) src;

  nativeBuildInputs = [ pkgs.unzip ];
  sourceRoot = ".";

  installPhase = ''
    mkdir -p $out
    cp -r * $out/
  '';
}
