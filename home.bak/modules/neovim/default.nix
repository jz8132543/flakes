{ pkgs, ... }:

{
  programs = {
    neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      plugins = with pkgs.vimPlugins; [
        vim-logreview
        vim-surround
        auto-pairs
        direnv-vim
        nerdtree
        nerdtree-git-plugin
        vim-rooter
        vim-polyglot
        vim-ragtag
        MatchTagAlways
        nerdcommenter
        vim-orgmode
        vim-easymotion
        fzf-vim
        editorconfig-vim
        vim-better-whitespace
        vim-signature
        incsearch-vim
        vim-over
        tabular
        ultisnips
        vim-snippets
        nvim-lspconfig
        vim-fugitive
        vim-signify
        NeoSolarized
        vim-airline
        vim-airline-clock
        indentLine
        vim-mundo
        { plugin = dracula-vim;
          optional = true;
        }
        vim-gnupg
        supertab
      ];

      extraConfig = ''
        " see github:nixos/nixpkgs#96062
        " This have to be done here instead of config option at below because
        " my configuration will load this.
        " packadd! dracula-vim
        " call vonfry#init()
      '';
    };
  };
}
