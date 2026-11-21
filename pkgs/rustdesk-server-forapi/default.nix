{
  lib,
  stdenv,
  fetchurl,
  unzip,
  autoPatchelfHook,
  glibc,
}:

stdenv.mkDerivation {
  pname = "rustdesk-server-forapi";
  version = "1.1.14-forapi-0.1.2";

  src = fetchurl {
    url = "https://github.com/lejianwen/rustdesk-server/releases/download/v0.1.2/rustdesk-server-linux-amd64.zip";
    hash = "sha256-v5aKxvdOY7APYIBHy76sSgFqtVLa60xi25ptBRjHsgk=";
  };

  nativeBuildInputs = [
    unzip
    autoPatchelfHook
  ];
  buildInputs = [ glibc ];
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    install -Dm755 hbbs $out/bin/hbbs
    install -Dm755 hbbr $out/bin/hbbr
    install -Dm755 rustdesk-utils $out/bin/rustdesk-utils
  '';

  meta = {
    description = "RustDesk Server fork with lejianwen API/JWT/WebSocket integration";
    homepage = "https://github.com/lejianwen/rustdesk-server";
    license = lib.licenses.agpl3Only;
    platforms = [ "x86_64-linux" ];
  };
}
