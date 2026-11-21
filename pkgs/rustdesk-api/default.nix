{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  tzdata,
}:

stdenv.mkDerivation {
  pname = "rustdesk-api";
  version = "2.7";

  src = fetchurl {
    url = "https://github.com/lejianwen/rustdesk-api/releases/download/v2.7/linux-amd64.tar.gz";
    hash = "sha256-0GiaNT/XVoFc/lYM58uY92RgLeYNBAO1HbTlqb2E0io=";
  };

  nativeBuildInputs = [ makeWrapper ];
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/libexec/rustdesk-api $out/bin
    cp -a . $out/libexec/rustdesk-api/
    makeWrapper $out/libexec/rustdesk-api/apimain $out/bin/rustdesk-api \
      --set ZONEINFO ${tzdata}/share/zoneinfo
  '';

  meta = {
    description = "RustDesk account, address book, admin and Web Client API";
    homepage = "https://github.com/lejianwen/rustdesk-api";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
