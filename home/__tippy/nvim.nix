{ pkgs, lib, inputs, ... }:

{
  programs.neovim = {
    enable = true;
    # package = pkgs.neovim-nightly;
    vimAlias = true;
    vimdiffAlias = true;
  };

  environment.persistence."/persist".users.tippy = {
    directories = [
      ".local/share/nvim"
      ".config/nvim"
    ];
  };
}
