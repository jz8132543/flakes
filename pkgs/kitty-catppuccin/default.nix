{
  fetchFromGitHub,
  stdenv,
  ...
}:
let
  version = "43098316202b84d6a71f71aaf8360f102f4d3f1a";
  src = fetchFromGitHub {
    owner = "catppuccin";
    repo = "kitty";
    rev = version;
    fetchSubmodules = false;
    sha256 = "sha256-akRkdq8l2opGIg3HZd+Y4eky6WaHgKFQ5+iJMC1bhnQ=";
  };
in
stdenv.mkDerivation {
  pname = "kitty-catppuccin";
  inherit version src;
  installPhase = ''
    mkdir -p $out
    mv themes/* $out
  '';
}
