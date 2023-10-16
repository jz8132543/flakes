{
  pkgs,
  config,
  ...
}: {
  programs.neovim = {
    enable = true;
    package = pkgs.neovim-nightly;
    viAlias = false;
    vimAlias = true;
    vimdiffAlias = true;
    withNodeJs = false;
    withRuby = false;
    withPython3 = false;
    defaultEditor = true;
    coc.enable = false;
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
      source = config.lib.file.mkOutOfStoreSymlink ../../source/nvim;
      recursive = true;
    };
  };

  home.global-persistence = {
    directories = [
      ".local/share/nvim"
      ".config/nvim"
      # ".config/coc"
    ];
  };
  home.packages = with pkgs; [
    unzip
    gnumake
  ];
}
