{
  lib,
  stdenv,
  wayland,
  wayland-protocols,
  wlr-protocols,
  libpng,
  systemd,
  pkg-config,
  wayland-scanner,
}:
stdenv.mkDerivation {
  pname = "hdr-wallpaper";
  version = "0.1.0";
  src = ./wallpaper.c;
  dontUnpack = true;
  strictDeps = true;

  nativeBuildInputs = [
    pkg-config
    wayland-scanner
  ];
  buildInputs = [
    wayland
    libpng
    systemd
  ];

  buildPhase = ''
    runHook preBuild
    for protocol in \
      ${wayland-protocols}/share/wayland-protocols/staging/color-management/color-management-v1.xml \
      ${wayland-protocols}/share/wayland-protocols/staging/fractional-scale/fractional-scale-v1.xml \
      ${wayland-protocols}/share/wayland-protocols/stable/viewporter/viewporter.xml \
      ${wayland-protocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml \
      ${wlr-protocols}/share/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml
    do
      name="$(basename "$protocol" .xml)"
      wayland-scanner client-header "$protocol" "$name-client-protocol.h"
      wayland-scanner private-code "$protocol" "$name-protocol.c"
    done
    $CC -std=c11 -O2 -Wall -Wextra -Werror \
      $(pkg-config --cflags wayland-client libpng libsystemd) -I. \
      "$src" ./*-protocol.c -o hdr-wallpaper \
      $(pkg-config --libs wayland-client libpng libsystemd) -lm
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    $CC -std=c11 -O2 -Wall -Wextra -Werror -DHDR_WALLPAPER_TEST \
      $(pkg-config --cflags wayland-client libpng libsystemd) -I. \
      "$src" ./*-protocol.c -o hdr-wallpaper-test \
      $(pkg-config --libs wayland-client libpng libsystemd) -lm
    env -u WAYLAND_DISPLAY -u WAYLAND_SOCKET ./hdr-wallpaper-test
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 hdr-wallpaper "$out/bin/hdr-wallpaper"
    runHook postInstall
  '';

  meta = {
    description = "Static fail-closed PQ BT.2020 Wayland HDR background";
    platforms = lib.platforms.linux;
    mainProgram = "hdr-wallpaper";
  };
}
