{
  lib,
  stdenvNoCC,
  sources,
}:
stdenvNoCC.mkDerivation {
  pname = "apple-pingfang-fonts";
  version = "unstable-${sources.apple-pingfang.date}";
  inherit (sources.apple-pingfang) src;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm444 $src $out/share/fonts/truetype/apple/PingFang.ttc
    runHook postInstall
  '';

  meta = with lib; {
    description = "Apple PingFang SC/TC/HK TrueType Collection fonts (6 weights: Ultralight, Thin, Light, Regular, Medium, Semibold)";
    homepage = "https://developer.apple.com/fonts/";
    license = licenses.unfree;
    platforms = platforms.all;
  };
}
