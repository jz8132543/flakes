{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  copyDesktopItems,
  cairo,
  dbus,
  gdk-pixbuf,
  glib,
  glib-networking,
  gtk3,
  libsoup_3,
  makeDesktopItem,
  webkitgtk_4_1,
  wrapGAppsHook3,
  ...
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "doubao-desktop";
  version = "1.2.0";

  src = fetchurl {
    url = "https://github.com/gonwe/doubao-desktop/releases/download/v${finalAttrs.version}/doubao-desktop-${finalAttrs.version}-x86_64.tar.gz";
    hash = "sha256-ys06p7GPH3FA71GUwumDpZ580Wzc2xcX++pu7ukTBL8=";
  };

  sourceRoot = "doubao-desktop-${finalAttrs.version}-x86_64";

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [
    autoPatchelfHook
    copyDesktopItems
    wrapGAppsHook3
  ];

  buildInputs = [
    cairo
    dbus
    gdk-pixbuf
    glib
    glib-networking
    gtk3
    libsoup_3
    webkitgtk_4_1
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "com.doubao.desktop";
      desktopName = "豆包";
      genericName = "AI Assistant";
      comment = "ByteDance AI intelligent assistant (Tauri native client)";
      exec = "doubao-desktop";
      icon = "doubao-desktop";
      terminal = false;
      type = "Application";
      categories = [
        "Network"
        "Chat"
        "Utility"
      ];
      keywords = [
        "doubao"
        "豆包"
        "AI"
        "bytedance"
        "chat"
        "tauri"
      ];
      startupWMClass = "com.doubao.desktop";
    })
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 doubao-desktop.bin $out/bin/doubao-desktop.bin
    install -Dm755 doubao-desktop $out/bin/doubao-desktop

    for size in 48 64 128 256; do
      install -Dm644 ''${size}x''${size}/doubao-desktop.png \
        $out/share/icons/hicolor/''${size}x''${size}/apps/doubao-desktop.png
    done

    runHook postInstall
  '';

  meta = with lib; {
    description = "Unofficial Doubao desktop client for Linux, built with Tauri";
    homepage = "https://github.com/gonwe/doubao-desktop";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "doubao-desktop";
  };
})
