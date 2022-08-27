{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [ vimPlugins.nvim-dap vimPlugins.nvim-dap-ui ];
  };
}
