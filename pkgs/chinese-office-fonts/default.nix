{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "chinese-office-fonts";
  version = "1.0.0-unstable-2025-05-21";

  src = fetchFromGitHub {
    owner = "DoveOutland";
    repo = "Common-Chinese-office-fonts-font-library-";
    rev = "0f5d77bdfad2e9bdfd03275111e2614caa88fff7";
    hash = "sha256-0WH8w3/NCMRG252vS/Wc5salTbmyuw4J8V6Jy5Tiv3g=";
  };

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
