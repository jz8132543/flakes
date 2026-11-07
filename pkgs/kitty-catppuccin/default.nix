{
  sources,
  stdenv,
  ...
}:
stdenv.mkDerivation {
  pname = "kitty-catppuccin";
  inherit (sources.kitty-catppuccin) version src;
  installPhase = ''
    mkdir -p $out
    mv themes/* $out
  '';
}
