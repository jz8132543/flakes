{
  fetchFromGitHub,
  stdenv,
  ...
}:
let
  version = "yaml";
  src = fetchFromGitHub {
    owner = "catppuccin";
    repo = "alacritty";
    rev = version;
    fetchSubmodules = false;
    sha256 = "sha256-w9XVtEe7TqzxxGUCDUR9BFkzLZjG8XrplXJ3lX6f+x0=";
  };
in
stdenv.mkDerivation {
  pname = "alacritty-catppuccin";
  inherit version src;
  installPhase = ''
    mkdir -p $out
    cp catppuccin-*.yml $out/
  '';
}
