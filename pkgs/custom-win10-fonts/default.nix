{
  stdenv,
  source,
  lib,
}:

stdenv.mkDerivation {
  inherit (source) pname version src;
  # name = "custom-win10-fonts";
  # unpackPhase = ":";
  # nativeBuildInputs = [ unzip ];
  # unpackPhase = ''
  #   unzip $src
  # '';

  installPhase = ''
    mkdir -p $out/share/fonts/truetype
    mv *.ttf $out/share/fonts/truetype
  '';

  meta = with lib; {
    description = "Custom Windows 10 fonts";
    homepage = "https://github.com/jz8132543/ttf-ms-win10";
    license = licenses.unfree; # 根据你的字体许可证进行调整
    platforms = platforms.all;
    maintainers = with maintainers; [ jz8132543 ]; # 替换为你的 GitHub 用户名
  };
}
