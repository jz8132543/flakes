{
  stdenvNoCC,
  lib,
  callPackage,
  ...
}:
let
  sources = callPackage ../_sources/generated.nix { };
  srcData =
    {
      "x86_64-linux" = sources.frp-panel-amd64;
      "aarch64-linux" = sources.frp-panel-arm64;
    }
    .${stdenvNoCC.hostPlatform.system}
      or (throw "Unsupported system for frp-panel: ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "frp-panel";
  inherit (srcData) version src;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/frp-panel"
    runHook postInstall
  '';

  meta = with lib; {
    description = "A multi-node FRP management panel and control plane";
    homepage = "https://github.com/VaalaCat/frp-panel";
    license = licenses.agpl3Only;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "frp-panel";
  };
}
