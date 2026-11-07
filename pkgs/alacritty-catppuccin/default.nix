{
  sources,
  stdenv,
  ...
}:
stdenv.mkDerivation {
  pname = "alacritty-catppuccin";
  version = "unstable-${sources.alacritty-catppuccin.date}";
  inherit (sources.alacritty-catppuccin) src;
  installPhase = ''
    mkdir -p $out
    cp catppuccin-*.yml $out/
  '';
}
