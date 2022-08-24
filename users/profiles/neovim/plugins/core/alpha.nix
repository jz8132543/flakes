{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      dashboard-nvim
    ];
  };
}
