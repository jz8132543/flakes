{ pkgs, lib, inputs, ... }:

{
  programs.neovim = {
    enable = true;
    # package = pkgs.neovim-nightly;
    vimAlias = true;
    vimdiffAlias = true;
  };

  home.packages = with pkgs; [
    nil
    nixpkgs-fmt
    nodejs
    yarn
    nodePackages.npm
    vimPlugins.coc-nvim
    watchman
  ];
  home.global-persistence = {
    directories = [
      ".local/share/nvim"
      ".config/nvim"
      ".config/coc"
    ];
  };
}
