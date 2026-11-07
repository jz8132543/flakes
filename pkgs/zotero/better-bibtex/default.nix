{
  jq,
  lib,
  stdenvNoCC,
  sources,
  unzip,
}:
stdenvNoCC.mkDerivation {
  pname = "zotero-better-bibtex";
  inherit (sources.zotero-better-bibtex) version src;

  dontUnpack = true;
  nativeBuildInputs = [
    jq
    unzip
  ];

  installPhase = ''
    runHook preInstall
    unzip -p "$src" manifest.json | jq -e --arg version "$version" \
      '.version == $version and .applications.zotero.id == "better-bibtex@iris-advies.com"'
    mkdir -p "$out"
    cp "$src" "$out/zotero-better-bibtex.xpi"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Make Zotero effective for us who also need to cite with BibTeX";
    homepage = "https://github.com/retorquere/zotero-better-bibtex";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
