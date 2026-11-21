{
  fetchurl,
  python3,
  runCommand,
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
  # Bang Qiao Yan, https://www.pixiv.net/en/artworks/108581486; no free redistribution license verified.
  showcaseSrc = fetchurl {
    url = "https://cdn.donmai.us/original/2f/74/2f746552ece426f97daf8d9bbda0ea77.png";
    name = "wallpaper-showcase.png";
    hash = "sha256-OKNf7d5Sa/hY3+uUUJGJnSgzz0mOzp/KiQF3eMLn1YU=";
  };
  imageTools.nativeBuildInputs = [
    (python3.withPackages (p: [
      p.numpy
      p.pillow
    ]))
  ];
in
stdenv.mkDerivation {
  pname = "wallpaper";
  inherit version src;
  passthru = {
    hdr = runCommand "wallpaper-hdr-pq-480" imageTools ''
      mkdir -p "$out"
      python3 ${./hdr.py} ${src} "$out/wallpaper-hdr.png"
    '';
    showcase = runCommand "wallpaper-showcase" { } ''
      install -Dm644 ${showcaseSrc} "$out/wallpaper.png"
    '';
    showcaseHdr = runCommand "wallpaper-showcase-hdr-pq-203" imageTools ''
      mkdir -p "$out"
      python3 ${./hdr.py} --preserve-sdr ${showcaseSrc} "$out/wallpaper-hdr.png"
    '';
    showcaseLockscreen = runCommand "wallpaper-showcase-lockscreen-original" { } ''
      install -Dm644 ${showcaseSrc} "$out/lockscreen.png"
    '';
  };
  unpackPhase = ":";
  installPhase = ''
    mkdir -p $out
    cp $src $out/wallpaper.jpg
  '';
}
