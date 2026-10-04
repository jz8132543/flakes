{
  fetchurl,
  lib,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation rec {
  pname = "zotero-better-bibtex";
  version = "7.0.3";

  src = fetchurl {
    url = "https://github.com/retorquere/zotero-better-bibtex/releases/download/v${version}/zotero-better-bibtex-${version}.xpi";
    hash = "sha256-42H5y00000000000000000000000000000000000000=";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp "$src" "$out/zotero-better-bibtex.xpi"
    runHook postInstall
  '';

  passthru.updateScript = {
    command = [
      "nix-update"
      pname
    ];
  };

  meta = with lib; {
    description = "Make Zotero effective for us who also need to cite with BibTeX";
    homepage = "https://github.com/retorquere/zotero-better-bibtex";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
