{
  pkgs,
  config,
  lib,
  ...
}:
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = false;
    vimAlias = true;
    vimdiffAlias = true;
    withNodeJs = true;
    withRuby = false;
    withPython3 = false;
    coc.enable = false;
    extraPackages = with pkgs; [
      (lua5_1.withPackages (
        ps: with ps; [
          luarocks
          luv
        ]
      ))
      imagemagick
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
  # xdg.dataFile."nvim/lazy/nvim-treesitter" = {
  #   source = "${pkgs.vimPlugins.nvim-treesitter.withAllGrammars.outPath}";
  #   recursive = true;
  #   force = true;
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
    gcc
    rust-bin.nightly.latest.minimal
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
}
