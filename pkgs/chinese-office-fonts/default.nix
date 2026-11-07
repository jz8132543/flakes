{
  lib,
  stdenvNoCC,
  sources,
}:
stdenvNoCC.mkDerivation {
  pname = "chinese-office-fonts";
  version = "unstable-${sources.chinese-office-fonts.date}";
  inherit (sources.chinese-office-fonts) src;

  installPhase = ''
    runHook preInstall
    install -Dm444 *.ttf *.ttc -t $out/share/fonts/truetype/chinese-office
    runHook postInstall
  '';

  meta = with lib; {
    description = "Common Chinese office and official document fonts (GB/T 9704-2012, SimHei, FangSong_GB2312, KaiTi_GB2312, FZXiaoBiaoSong)";
    homepage = "https://github.com/DoveOutland/Common-Chinese-office-fonts-font-library-";
    license = licenses.unfree;
    platforms = platforms.all;
  };
}
