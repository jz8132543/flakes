{ config, pkgs, ... }:

{
  # Allow unfree
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = (pkg: true);
  home.packages = with pkgs;[
    pkgs.cachix
    thefuck
    bottom
    exa bat fzf fd
    age pinentry sequoia #gnupg
    sops
    nixfmt
  ];
}
