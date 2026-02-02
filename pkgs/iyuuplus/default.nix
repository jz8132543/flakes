{ stdenv, source }:

stdenv.mkDerivation {
  inherit (source) pname version src;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/iyuuplus
    cp -r . $out/share/iyuuplus
    runHook postInstall
  '';

  meta = {
    description = "IYUUPlus - Auto Reseed and Cross-Seed Tool";
    homepage = "https://gitee.com/ledc/iyuuplus";
    license = "Proprietary"; # Check license? Assuming proprietary or unknown for now.
  };
}
