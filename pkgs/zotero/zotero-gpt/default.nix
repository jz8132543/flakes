{
  fetchurl,
  lib,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation rec {
  pname = "zotero-gpt";
  version = "3.1.4";

  src = fetchurl {
    url = "https://github.com/MuiseDestiny/zotero-gpt/releases/download/${version}/zotero-gpt.xpi";
    hash = "sha256-8wu/0E37wNxxRKajKGwNMVw2ayHA2FN0u8u8Q+Y7vXU=";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp "$src" "$out/zotero-gpt.xpi"
    runHook postInstall
  '';

  passthru.updateScript = {
    command = [
      "nix-update"
      pname
    ];
  };

  meta = with lib; {
    description = "Zotero AI/GPT plugin supporting custom API proxy & LLMs";
    homepage = "https://github.com/MuiseDestiny/zotero-gpt";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
