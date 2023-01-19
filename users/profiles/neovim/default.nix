{ pkgs, lib, inputs, ... }:

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
      ".config/nvim"
    ];
  };
  # home.file.neovim = {
  #   source = inputs.nvim-config;
  #   target = ".config/nvim";
  #   recursive = true;
  # };
}
