{
  stdenv,
  lib,
  callPackage,
}:
let
  sources = callPackage ../_sources/generated.nix { };
  inherit (stdenv.hostPlatform) system;

  selectSource = {
    "x86_64-linux" = sources.frp-panel-amd64;
    "aarch64-linux" = sources.frp-panel-arm64;
  };

  selectClientSource = {
    "x86_64-linux" = sources.frp-panel-client-amd64;
    "aarch64-linux" = sources.frp-panel-client-arm64;
  };

  srcData = selectSource.${system} or (throw "Unsupported system: ${system}");
  clientSrcData = selectClientSource.${system} or (throw "Unsupported system: ${system}");

in
stdenv.mkDerivation {
  pname = "frp-panel";
  inherit (srcData) version;

  # We use the full binary as the main package
  # but we also provide a 'client' output or separate package if needed.
  # For simplicity, we'll install both and the user can choose.

  srcs = [
    srcData.src
    clientSrcData.src
  ];

  unpackPhase = "true";

  installPhase = ''
    mkdir -p $out/bin
    cp ${srcData.src} $out/bin/frp-panel
    cp ${clientSrcData.src} $out/bin/frp-panel-client
    chmod +x $out/bin/*
  '';

  meta = with lib; {
    description = "A multi node frp webui and for frp server and client management";
    homepage = "https://github.com/VaalaCat/frp-panel";
    license = licenses.agpl3Only;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "frp-panel";
  };
}
