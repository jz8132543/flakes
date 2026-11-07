{
  jq,
  lib,
  stdenvNoCC,
  sources,
  unzip,
}:
let
  updates = builtins.fromJSON (builtins.readFile sources.zotero-gpt.extract."update.json");
in
stdenvNoCC.mkDerivation {
  pname = "zotero-gpt";
  inherit ((builtins.head updates.addons."zoterogpt@polygon.org".updates)) version;
  src = "${sources.zotero-gpt.src}/zotero-gpt.xpi";

  dontUnpack = true;
  nativeBuildInputs = [
    jq
    unzip
  ];

  installPhase = ''
    runHook preInstall
    unzip -p "$src" manifest.json | jq -e --arg version "$version" \
      '.version == $version and .applications.zotero.id == "zoterogpt@polygon.org"'
    mkdir -p "$out"
    cp "$src" "$out/zotero-gpt.xpi"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Zotero AI/GPT plugin supporting custom API proxy & LLMs";
    homepage = "https://github.com/MuiseDestiny/zotero-gpt";
    license = licenses.unfree;
    platforms = platforms.all;
  };
}
