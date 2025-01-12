{
  pkgs,
  config,
  lib,
  ...
}:
{
  programs.neovim = {
    enable = true;
    # package = pkgs.neovim-nightly;
    # package = pkgs.neovim.override {
    #   lua = pkgs.luajit;
    # };
    viAlias = false;
    vimAlias = true;
    vimdiffAlias = true;
    withNodeJs = false;
    withRuby = false;
    withPython3 = false;
    defaultEditor = true;
    coc.enable = false;
    # plugins = [ pkgs.vimPlugins.nvim-treesitter.withAllGrammars ];
    extraPackages = with pkgs; [
      # luajitPackages.luarocks
      # lsps
      nil
      nixd
      lua-language-server
      terraform-ls
      nodePackages.vscode-langservers-extracted # css,eslint,html,json,markdown
      nodePackages.typescript
      nodePackages.typescript-language-server
      nodePackages.bash-language-server
      nodePackages.dockerfile-language-server-nodejs
      # formatters
      eslint_d
      prettierd
      nodePackages.prettier
    ];
  };

  home.sessionVariables = {
    MANPAGER = "nvim -c 'Man!' -o -";
  };

  xdg.configFile = {
    "ripgrep_ignore".text = ''
      .git/
      yarn.lock
      package-lock.json
      packer_compiled.lua
      .DS_Store
      .netrwhist
      dist/
      node_modules/
      **/node_modules/
      wget-log
      wget-log.*
      /vendor
    '';
    "nvim" = {
      source = config.lib.file.mkOutOfStoreSymlink "/home/${baseNameOf ./.}/source/nvim";
      recursive = true;
    };
  };
  xdg.dataFile."nvim/site/parser" = {
    # source = "${pkgs.vimPlugins.nvim-treesitter.withAllGrammars.outPath}";
    source =
      let
        parsersPath = pkgs.symlinkJoin {
          name = "treesitter-parsers";
          paths = pkgs.vimPlugins.nvim-treesitter.withAllGrammars.dependencies;
        };
      in
      "${parsersPath}/parser";
    recursive = true;
    force = true;
  };
  # home.file."./.local/share/nvim/my-local-lazy/nvim-treesitter/" = {
  #   recursive = true;
  #   source = pkgs.vimPlugins.nvim-treesitter.withAllGrammars;
  # };

  home.global-persistence = {
    directories = [
      ".cargo"
      ".local/share/nvim"
      # ".config/nvim"
      # ".config/coc"
    ];
  };
  home.packages = with pkgs; [
    unzip
    gnumake
    luajitPackages.luarocks-nix
    gcc
    rust-bin.nightly.latest.minimal
    # luarocks-nix
    # luajit
  ];
}
