{
  stdenv,
  fetchFromGitHub,
  lib,
}:

stdenv.mkDerivation {
  pname = "custom-win10-fonts";
  version = "1.0";

  src = fetchFromGitHub {
    owner = "jz8132543";
    repo = "ttf-ms-win10";
    rev = "4adc0a4198cc090b63bcb667363c03101e8175eb"; # 替换为你的仓库的特定 commit hash 或 tag
    sha256 = "11iv3jdsfniyhznmnz552k2w8b9bz54cj3cgc6v5z5i0wqdq8ad7"; # 替换为你的仓库的 sha256 校验和
  };

  installPhase = ''
    mkdir -p $out/share/fonts/truetype
    cp -r $src/*.ttf $out/share/fonts/truetype/
  '';

  meta = with lib; {
    description = "Custom Windows 10 fonts";
    homepage = "https://github.com/jz8132543/ttf-ms-win10";
    license = licenses.unfree; # 根据你的字体许可证进行调整
    platforms = platforms.all;
    maintainers = with maintainers; [ jz8132543 ]; # 替换为你的 GitHub 用户名
  };
}
