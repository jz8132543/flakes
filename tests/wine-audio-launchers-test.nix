{
  pkgs,
  home,
  bitwigPackage,
}:
let
  names = [
    "garritan-cfx"
    "garritan-cfx-desktop"
    "vsl-concert-d274"
    "vsl-concert-d274-desktop"
    "com.bitwig.BitwigStudio"
  ];
  files = map (name: home.xdg.dataFile."applications/${name}.desktop".source) names;
  managedFiles = builtins.attrValues (pkgs.lib.filterAttrs (_: file: file.enable) home.home.file);
in
assert home.home.homeDirectory == "/home/tippy";
assert home.home.profileDirectory == "/mnt/games/Audio/.launcher-state/nix/profile";
assert !home.systemd.user.enable;
assert builtins.length managedFiles == 5;
assert builtins.all (
  file: builtins.any (name: pkgs.lib.hasSuffix "applications/${name}.desktop" file.target) names
) managedFiles;
pkgs.runCommand "wine-audio-launchers-test"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    python3 ${./wine-audio-desktop-entries-test.py} \
      ${pkgs.lib.getLib pkgs.glib}/lib/libglib-2.0.so.0 ${bitwigPackage} \
      ${builtins.concatStringsSep " " files} > "$out"
  ''
