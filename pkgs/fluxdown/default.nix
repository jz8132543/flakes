{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  wrapGAppsHook3,
  alsa-lib,
  dbus,
  fontconfig,
  freetype,
  gtk3,
  libayatana-appindicator,
  libx11,
  libxcb,
  libxkbcommon,
  vulkan-loader,
  wayland,
  xdotool,
  xdg-utils,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "fluxdown";
  version = "0.6.8";

  src = fetchurl {
    url = "https://github.com/zerx-lab/FluxDown/releases/download/v${finalAttrs.version}/FluxDown-${finalAttrs.version}-linux-x64.deb";
    hash = "sha256-sZR6NWrZAodlXQA7+i9PYRTAN8ShcBIOKUhDUH0+ibE=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    wrapGAppsHook3
  ];
  buildInputs = [
    alsa-lib
    dbus
    fontconfig
    freetype
    gtk3
    libayatana-appindicator
    libx11
    libxcb
    libxkbcommon
    vulkan-loader
    wayland
    xdotool
  ];
  # GPUI and the tray load these libraries dynamically.
  runtimeDependencies = map lib.getLib [
    libayatana-appindicator
    libxkbcommon
    vulkan-loader
    wayland
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    # All four executables discover their siblings through current_exe().
    mkdir -p "$out/bin"
    for executable in fluxdown-desktop fluxdown-agent fluxdownd fluxdown_nmh; do
      install -m755 "opt/fluxdown/$executable" "$out/bin/$executable"
    done
    cp -r usr/share "$out/share"
    runHook postInstall
  '';
  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : ${lib.makeBinPath [ xdg-utils ]})
  '';

  meta = {
    description = "Multi-protocol download manager with native browser integration";
    homepage = "https://fluxdown.com";
    changelog = "https://github.com/zerx-lab/FluxDown/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.agpl3Only;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "fluxdown-desktop";
  };
})
