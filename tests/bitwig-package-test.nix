{
  pkgs,
  package,
  hostPackages,
}:
let
  manifest = builtins.fromJSON (builtins.readFile ../pkgs/bitwig-studio/sources.json);
  original = package.override {
    applyJarPatch = false;
    requireFile =
      asset:
      if asset.name == "bitwig.jar" then
        throw "The original Bitwig package must not require the replacement JAR"
      else
        pkgs.requireFile asset;
  };
  jar = pkgs.requireFile {
    inherit (manifest.jar) name hash;
    message = "Import the version-matched bitwig.jar to run this packaging test.";
  };
in
assert package.version == "6.0";
assert package.applyJarPatch && !original.applyJarPatch;
assert original.postInstall == (pkgs.bitwig-studio6.postInstall or "");
assert original.drvPath != package.drvPath;
assert builtins.any (
  installed:
  (installed.pname or "") == "bitwig-studio"
  && (installed.version or "") == package.version
  && (installed.applyJarPatch or false)
) hostPackages;
pkgs.runCommand "bitwig-package-test" { } ''
  test -x ${package}/bin/bitwig-studio
  test -x ${package}/libexec/bitwig-studio
  test -f ${package}/share/applications/com.bitwig.BitwigStudio.desktop
  test ! -e ${package}/libexec/lib/bitwig-studio/libxcb-imdkit.so.1
  cmp ${jar} ${package}/libexec/bin/bitwig.jar
  touch "$out"
''
