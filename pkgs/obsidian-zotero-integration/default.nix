{
  fetchzip,
  lib,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation rec {
  pname = "obsidian-zotero-integration";
  version = "1.0.3";

  src = fetchzip {
    url = "https://github.com/mgmeyers/obsidian-zotero-desktop-connector/releases/download/${version}/obsidian-zotero-desktop-connector-${version}.zip";
    hash = "sha256-42H5y00000000000000000000000000000000000000=";
  };

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r * "$out/"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Insert and link citations and bibliographies from Zotero";
    homepage = "https://github.com/mgmeyers/obsidian-zotero-desktop-connector";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
