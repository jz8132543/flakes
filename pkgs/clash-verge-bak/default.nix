{
  source,
  lib,
  stdenv,
  dpkg,
  wrapGAppsHook,
  autoPatchelfHook,
  clash,
  clash-meta,
  openssl,
  webkitgtk,
  udev,
  libayatana-appindicator,
}:
stdenv.mkDerivation {
  inherit (source) pname version src;

  nativeBuildInputs = [
    dpkg
    wrapGAppsHook
    autoPatchelfHook
  ];

  buildInputs = [
    openssl
    webkitgtk
    stdenv.cc.cc
  ];

  runtimeDependencies = [
    (lib.getLib udev)
    libayatana-appindicator
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    mv usr/* $out
    rm $out/bin/{clash,clash-meta}

    runHook postInstall
  '';

  postFixup = ''
    ln -s ${lib.getExe clash} $out/bin/clash
    ln -s ${lib.getExe clash-meta} $out/bin/clash-meta
  '';
}