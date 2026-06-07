{
  bash,
  bc,
  curl,
  dnsutils,
  fetchurl,
  iproute2,
  jq,
  lib,
  makeWrapper,
  netcat-openbsd,
  nexttrace,
  stdenv,
  wget,
  ...
}:
let
  version = "V1.2";
  src = fetchurl {
    url = "https://cdn.kxy.ovh/kxy.sh";
    sha256 = "sha256-jOlBBLIjT0lYKPkgxIKaUGwuEeR/O4rupG1SpZ4n8pw=";
  };
in
stdenv.mkDerivation {
  pname = "kxy-script";
  inherit version src;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cp $src $out/bin/kxy
    chmod +x $out/bin/kxy

    wrapProgram $out/bin/kxy \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          curl
          wget
          jq
          bc
          netcat-openbsd
          dnsutils
          iproute2
          nexttrace
        ]
      }
  '';

  meta = with lib; {
    description = "KXY server management toolbox script";
    homepage = "https://cdn.kxy.ovh/kxy.sh";
    license = licenses.mit;
    mainProgram = "kxy";
  };
}
