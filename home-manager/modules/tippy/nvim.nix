{
  pkgs,
  config,
  ...
}:
let
  mkSymlink = config.lib.file.mkOutOfStoreSymlink;
in
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = false;
    vimAlias = true;
    vimdiffAlias = true;
    withNodeJs = true;
    withRuby = true;
    withPython3 = true;
    coc.enable = false;
    extraPackages = with pkgs; [
      clang
      luarocks
      lua
      nodejs
      tree-sitter
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
  home.file = {
    ".config/nvim-plugins".source =
      let
        packDir = pkgs.vimUtils.packDir config.programs.neovim.finalPackage.passthru.packpathDirs;
      in
      mkSymlink "${packDir}/pack/myNeovimPackages/start";

    ".config/nvim-treesitter-parsers".source =
      let
        nvim-treesitter-parsers = pkgs.symlinkJoin {
          name = "nvim-treesitter-parsers";
          paths =
            (pkgs.vimPlugins.nvim-treesitter.withPlugins (
              plugins:
              let
                allowed = [
                  "bash"
                  "c"
                  "cmake"
                  "cpp"
                  "css"
                  "dockerfile"
                  "fish"
                  "gitcommit"
                  "gitignore"
                  "go"
                  "gomod"
                  "gosum"
                  "hcl"
                  "html"
                  "javascript"
                  "json"
                  "lua"
                  "make"
                  "markdown"
                  "markdown_inline"
                  "nix"
                  "python"
                  "query"
                  "regex"
                  "rust"
                  "sql"
                  "terraform"
                  "toml"
                  "tsx"
                  "typescript"
                  "vim"
                  "vimdoc"
                  "yaml"
                ];
              in
              builtins.filter (
                p: builtins.any (lang: builtins.match ".*tree-sitter-${lang}.*" (p.name or "") != null) allowed
              ) (builtins.attrValues plugins)
            )).dependencies;
        };
      in
      mkSymlink nvim-treesitter-parsers;
  };

  home.global-persistence = {
    directories = [
      ".cargo"
      ".local/share/nvim"
      # ".config/nvim"
      # ".config/coc"
    ];
  };
  home.packages = with pkgs; [
  ];
}
