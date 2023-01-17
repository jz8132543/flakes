{ pkgs, lib, ... }:

{
  programs.neovim = {
    enable = true;
    vimAlias = true;
    vimdiffAlias = true;
  };

  home.packages = with pkgs; [
    nil
    nixpkgs-fmt
    nix-ld
    nodejs
    nodePackages.npm
    sumneko-lua-language-server
    stylua
    luajitPackages.luacheck
    clang
  ];
  home.global-persistence = {
    directories = [
      ".local/share/nvim"
    ];
  };
  home.file.neovim = {
    source = ./nvim;
    target = ".config/nvim";
    recursive = true;
  };
}
