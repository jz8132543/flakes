{ pkgs, lib, ... }:

{
  imports = [./plugins];

  programs = {
    neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
    };
  };

  home.file.neovim = {
    source = ./lua;
    target = ".config/nvim/lua";
    recursive = true;
  };

  home.packages = with pkgs; [
    rnix-lsp
  ];
}
