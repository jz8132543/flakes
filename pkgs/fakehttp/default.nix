{
  fetchurl,
  lib,
  stdenvNoCC,
  ...
}:
let
  version = "0.9.18";
  src = fetchurl {
    url = "https://github.com/MikeWang000000/FakeHTTP/releases/download/${version}/fakehttp-linux-x86_64.tar.gz";
    sha256 = "sha256-DNvjQndYez6f+BF+YTDV241xa7nFFDRAiEpSftHVv8k=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "fakehttp";
  inherit version src;

  # 源码是预编译静态二进制（musl），无需编译
  dontBuild = true;
  dontConfigure = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 fakehttp $out/bin/fakehttp
    runHook postInstall
  '';

  meta = with lib; {
    description = "Obfuscate TCP connections as HTTP to bypass ISP whitelist QoS throttling";
    homepage = "https://github.com/MikeWang000000/FakeHTTP";
    license = licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "fakehttp";
  };
}
