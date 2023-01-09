{ pkgs, lib, ... }:

{
  programs.neovim = {
    enable = true;
    vimAlias = true;
    vimdiffAlias = true;
  };

  home.packages = with pkgs; [
    nil
    nodejs
    nodePackages.npm
    sumneko-lua-language-server
  ];
  home.global-persistence = {
    directories = [
      ".local/share/nvim"
    ];
  };
  home.file.neovim = {
    source = ./config;
    target = ".config/nvim";
    recursive = true;
  };
}
