{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      {
        plugin = nur.repos.m15a.vimExtraPlugins.rose-pine;
        config = ''
	        vim.cmd('colorscheme rose-pine')
        '';
      }
    ];
  };
}
