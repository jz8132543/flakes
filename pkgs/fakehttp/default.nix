{
  stdenvNoCC,
  source,
  lib,
  ...
}:
stdenvNoCC.mkDerivation {
  pname = "fakehttp";
  inherit (source) version src;

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
