{
  lib,
  appimageTools,
  fetchurl,
}:
let
  pname = "linglong-store";
  version = "3.7.0";
  src = fetchurl {
    url = "https://github.com/HanHan666666/flutter-linglong-store/releases/download/v${version}/${pname}-${version}-amd64.AppImage";
    hash = "sha256-R1sZsqIVVwnFaUoxCQkVqOjaJj25XVTdO9d+C52mLxs=";
  };
  extracted = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapAppImage {
  inherit pname version src;
  contents = extracted;
  extraPkgs = pkgs: [ pkgs.gtk3 ];
  extraInstallCommands = ''
    install -Dm444 ${extracted}/usr/share/applications/linglong-store.desktop $out/share/applications/linglong-store.desktop
    install -Dm444 ${extracted}/usr/share/icons/hicolor/256x256/apps/linglong-store.png $out/share/icons/hicolor/256x256/apps/linglong-store.png
  '';
  meta = {
    description = "Community graphical application store for Linyaps";
    homepage = "https://github.com/HanHan666666/flutter-linglong-store";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
