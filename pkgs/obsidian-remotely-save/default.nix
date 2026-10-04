{
  fetchzip,
  lib,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation rec {
  pname = "obsidian-remotely-save";
  version = "0.5.25";

  src = fetchzip {
    url = "https://github.com/remotely-save/remotely-save/releases/download/${version}/remotely-save-${version}.zip";
    hash = "sha256-42H5y00000000000000000000000000000000000000=";
  };

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r * "$out/"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Sync Obsidian vault with WebDAV/S3/OneDrive/Dropbox";
    homepage = "https://github.com/remotely-save/remotely-save";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
