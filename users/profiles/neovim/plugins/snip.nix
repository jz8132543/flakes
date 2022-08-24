{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      vimPlugins.luasnip
      vimPlugins.cmp_luasnip
    ];
  };
}
