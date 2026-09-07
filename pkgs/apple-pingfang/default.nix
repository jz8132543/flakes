{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation rec {
  pname = "apple-pingfang-fonts";
  version = "1.0.0";

  src = fetchurl {
    url = "https://raw.githubusercontent.com/ZWolken/PingFang/main/TrueType_Collection_format/PingFang.ttc";
    hash = "sha256-gyC24au46C2hMQmukddIVP2ACjIPYvi1wDiko2NdrNw=";
  };

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
