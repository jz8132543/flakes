{
  pkgs,
  config,
  ...
}:
{
  programs.neovim = {
    enable = true;
    # package = pkgs.neovim-nightly;
    viAlias = false;
    vimAlias = true;
    vimdiffAlias = true;
    withNodeJs = false;
    withRuby = false;
    withPython3 = false;
    defaultEditor = true;
    coc.enable = false;
    extraLuaPackages =
      p: with p; [
        luarocks
        magick
      ];
    extraPackages = with pkgs; [
      clang
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
  ];
}
