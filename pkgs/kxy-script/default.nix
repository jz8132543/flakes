{
  source,
  stdenv,
  makeWrapper,
  curl,
  wget,
  jq,
  bc,
  netcat-openbsd,
  dnsutils,
  iproute2,
  nexttrace,
  lib,
  bash,
}:
stdenv.mkDerivation {
  inherit (source) pname version src;

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
