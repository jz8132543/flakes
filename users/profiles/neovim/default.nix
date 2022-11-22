{ pkgs, lib, ... }:

{
  programs = {
    neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
    };
  };

  home.packages = with pkgs; [ 
    gnumake cmake
    gcc 
    rnix-lsp 
    sumneko-lua-language-server 
    luajitPackages.luacheck
    luaformatter
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
