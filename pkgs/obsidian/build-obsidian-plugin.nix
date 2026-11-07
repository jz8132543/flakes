{
  lib,
  jq,
  stdenvNoCC,
}:
{
  pname,
  main,
  manifest,
  css ? null,
  description ? "Obsidian plugin",
  homepage,
  license ? lib.licenses.mit,
  passthru ? { },
}:
assert main.version == manifest.version;
assert css == null || css.version == manifest.version;
stdenvNoCC.mkDerivation {
  inherit pname;
  version = lib.removePrefix "v" manifest.version;
  srcMain = main.src;
  srcManifest = manifest.src;
  srcCss = if css == null then null else css.src;

  dontUnpack = true;
  nativeBuildInputs = [ jq ];

  installPhase = ''
    runHook preInstall
    jq -e --arg version "$version" '.version == $version' "$srcManifest"
    mkdir -p "$out"
    cp "$srcMain" "$out/main.js"
    cp "$srcManifest" "$out/manifest.json"
    if [ -n "$srcCss" ]; then
      cp "$srcCss" "$out/styles.css"
    fi
    runHook postInstall
  '';

  inherit passthru;

  meta = {
    inherit description homepage license;
    platforms = lib.platforms.all;
  };
}
