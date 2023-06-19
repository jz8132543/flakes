{
  stdenv,
  iosevka-dora,
  nerd-font-patcher,
}:
stdenv.mkDerivation {
  name = "iosevka-dora-nf";
  src = iosevka-dora;
  nativeBuildInputs = [
    nerd-font-patcher
  ];
  enableParallelBuilding = true;
  unpackPhase = ''
    mkdir -p fonts
    cp -r $src/share/fonts/truetype/. ./fonts/
    chmod u+w -R ./fonts
  '';
  postPatch = ''
    cp ${./NerdFontMakefile} ./Makefile
  '';
}
