{ pkgs, lib, inputs, ... }:

{
  programs.neovim = {
    enable = true;
    # package = pkgs.neovim-nightly;
    vimAlias = true;
    vimdiffAlias = true;
  };

  home.persistence."/nix/persist/home/tippy" = {
    directories = [
      "source"
      ".local/share/direnv"
      ".local/share/containers"
    ];
  };
}
