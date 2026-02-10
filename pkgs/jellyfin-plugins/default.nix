{
  pkgs,
  ...
}:
let
  sources = pkgs.callPackage ../_sources/generated.nix { };
  mkPlugin =
    name:
    pkgs.stdenv.mkDerivation {
      pname = name;
      inherit (sources.${name}) version src;
      nativeBuildInputs = [ pkgs.unzip ];
      sourceRoot = ".";
      installPhase = ''
        mkdir -p $out
        # Find the directory containing the main DLL and copy its contents
        # This handles zips that might have a top-level folder
        DIR=$(find . -name "*.dll" -exec dirname {} \; | head -n 1)
        if [ -n "$DIR" ]; then
          cp -r "$DIR"/* $out/
        else
          cp -r * $out/
        fi
      '';
    };
in
{
  intro-skipper = mkPlugin "jellyfin-plugin-intro-skipper";
  playback-reporting = mkPlugin "jellyfin-plugin-playback-reporting";
  bangumi = mkPlugin "jellyfin-plugin-bangumi";
  shokofin = mkPlugin "jellyfin-plugin-shokofin";
  ani-sync = mkPlugin "jellyfin-plugin-ani-sync";
  bazarr = mkPlugin "jellyfin-plugin-bazarr";
  merge-versions = mkPlugin "jellyfin-plugin-merge-versions";
  skin-manager = mkPlugin "jellyfin-plugin-skin-manager";
  tmdb-box-sets = mkPlugin "jellyfin-plugin-tmdb-box-sets";
  douban = mkPlugin "jellyfin-plugin-douban";
  fanart = mkPlugin "jellyfin-plugin-fanart";
  sso = mkPlugin "jellyfin-plugin-sso";

  metatube = mkPlugin "jellyfin-plugin-metatube";
}
