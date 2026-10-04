{
  fetchzip,
  lib,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation rec {
  pname = "obsidian-copilot";
  version = "2.6.2";

  src = fetchzip {
    url = "https://github.com/logancyang/obsidian-copilot/releases/download/${version}/obsidian-copilot-${version}.zip";
    hash = "sha256-42H5y00000000000000000000000000000000000000=";
  };

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r * "$out/"
    runHook postInstall
  '';

  meta = with lib; {
    description = "A ChatGPT Copilot in Obsidian";
    homepage = "https://github.com/logancyang/obsidian-copilot";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
