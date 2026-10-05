{
  lib,
  stdenvNoCC,
  fetchurl,
}:
{
  pname,
  version,
  author,
  repo ? pname,
  hashJs,
  hashManifest,
  hashCss ? null,
  description ? "Obsidian plugin",
  homepage ? "https://github.com/${author}/${repo}",
  license ? lib.licenses.mit,
  passthru ? { },
}:
stdenvNoCC.mkDerivation {
  inherit pname version;

  srcMain = fetchurl {
    url = "https://github.com/${author}/${repo}/releases/download/${version}/main.js";
    hash = hashJs;
  };

  srcManifest = fetchurl {
    url = "https://github.com/${author}/${repo}/releases/download/${version}/manifest.json";
    hash = hashManifest;
  };

  srcCss =
    if (hashCss != null) then
      (fetchurl {
        url = "https://github.com/${author}/${repo}/releases/download/${version}/styles.css";
        hash = hashCss;
      })
    else
      null;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
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
