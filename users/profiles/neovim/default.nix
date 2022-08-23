{ pkgs, lib, ... }:

{
  imports = ./plugins;

  programs = {
    neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
    };
  };
}
