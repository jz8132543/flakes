{
  pkgs,
  config,
  ...
}:
{
  programs.neovim = {
    enable = true;
    # package = pkgs.neovim-nightly;
    package = pkgs.neovim.override {
      lua = pkgs.luajit;
    };
    viAlias = false;
    vimAlias = true;
    vimdiffAlias = true;
    withNodeJs = false;
    withRuby = false;
    withPython3 = false;
    defaultEditor = true;
    coc.enable = false;
    plugins = [ pkgs.vimPlugins.nvim-treesitter.withAllGrammars ];
    extraPackages = with pkgs; [
      luajitPackages.luarocks
      gcc
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

  home.global-persistence = {
    directories = [
      ".local/share/nvim"
      # ".config/nvim"
      # ".config/coc"
    ];
  };
  home.packages = with pkgs; [
    unzip
    gnumake
    # luarocks-nix
    # luajit
  ];
}
