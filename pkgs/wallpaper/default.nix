{
  fetchurl,
  stdenv,
  ...
}:
let
  version = "latest";
  src = fetchurl {
    url = "https://files.yande.re/image/3fc51f6a2fb10c96b73dd0fce6ddb9c8/yande.re%201048717%20dress%20garter%20lolita_fashion%20ruo_gan_zhua.jpg";
    name = "wallpaper.jpg";
    sha256 = "sha256-wkiXDN6vPFtx88krcQ4szK6dJNjtrDxrsNa3ZvHlfMQ=";
  };
in
stdenv.mkDerivation {
  pname = "wallpaper";
  inherit version src;
  unpackPhase = ":";
  installPhase = ''
    mkdir -p $out
    cp $src $out/wallpaper.jpg
  '';
}
