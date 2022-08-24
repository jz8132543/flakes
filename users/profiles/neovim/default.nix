{ pkgs, lib, ... }:

{

  imports = [./plugins];

  programs = {
    neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
      extraConfig = ''
        lua require("core")
      '';
    };
  };

  home.file.neovim = {
    source = ./nvim/lua;
    target = ".config/nvim/lua";
    recursive = true;
  };

  home.packages = with pkgs; [
    rnix-lsp
  ];
}
