{
  lib,
  stdenv,
  nodejs,
  makeWrapper,
  ...
}:

stdenv.mkDerivation {
  pname = "kaogong-helper";
  version = "1.0.0";

  src = ./src;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/lib/kaogong-helper $out/bin
    cp -r * $out/lib/kaogong-helper/

    makeWrapper ${nodejs}/bin/node $out/bin/kaogong-helper \
      --add-flags "$out/lib/kaogong-helper/server.js"
  '';

  meta = {
    description = "Civil Service Exam Prep System (考公备考辅助系统)";
    homepage = "https://github.com/jz8132543/flakes";
    license = lib.licenses.mit;
    mainProgram = "kaogong-helper";
  };
}
