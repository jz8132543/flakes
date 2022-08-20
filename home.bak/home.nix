{ config, pkgs, ... }:

{
  imports = [
    ./modules/sops
    ./modules/zsh
    ./modules/neovim
    ./modules/ssh
    ./modules/git
    ./modules/gpg
    ./pkgs.nix
  ];
  home = {
    username = "tippy";
    homeDirectory = "/home/tippy";
    stateVersion = "22.05";
  };
}
