{
  pkgs,
  config,
  lib,
  ...
}:
let
  catppuccin = pkgs.catppuccin.override {
    inherit (config.home.catppuccin) variant;
    inherit (config.home.catppuccin) accent;
  };
  toTitle =
    str: "${lib.toUpper (lib.substring 0 1 str)}${lib.substring 1 (lib.stringLength str) str}";
in
with config.home.catppuccin;
{
  programs = {
    starship = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      enableFishIntegration = true;
      settings = {
        palette = "catppuccin_${flavor}";
      } // builtins.fromTOML (builtins.readFile "${catppuccin}/starship/${flavor}.toml");
    };
    fzf = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      enableFishIntegration = true;
      tmux.enableShellIntegration = true;
    };
    zoxide = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      enableFishIntegration = true;
    };
    eza = {
      enable = true;
      enableZshIntegration = true;
      git = true;
      icons = "auto";
    };
    bat = {
      enable = true;
      config = {
        pager = "less -FR";
        # theme = "Catppuccin\ ${toTitle flavor}";
        theme = "catppuccin-${flavor}";
      };
      themes = {
        "catppuccin-${config.home.catppuccin.flavor}" = {
          src = catppuccin;
          file = "bat/Catppuccin\ ${toTitle flavor}.tmTheme";
        };
      };
    };
    # bottom = {settings = {} // builtins.fromTOML (builtins.readFile "${catppuccin}/bottom/${flavor}.toml");};
    zsh = {
      enable = true;
      history.path = "$HOME/.local/share/zsh/zsh_history";
      dotDir = ".config/zsh";
      defaultKeymap = "emacs";

      enableVteIntegration = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      autocd = true;
      enableCompletion = true;

      shellAliases = {
        # ls = "${pkgs.eza}/bin/eza --icons=auto";
        # tree = "${pkgs.eza}/bin/eza --tree --icons=auto";
        top = "${pkgs.bottom}/bin/btm --enable_cache_memory --battery";
        cat = "${pkgs.bat}/bin/bat --style=plain";
        fzf = "${pkgs.fzf}/bin/fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}'";
        batdiff = "git diff --name-only --relative --diff-filter=d | xargs ${pkgs.bat}/bin/bat --diff";
        rg = "${pkgs.ripgrep}/bin/rg --no-ignore";
        rsync = "${pkgs.rsync}/bin/rsync -arvzP";
      };
      initExtraBeforeCompInit = ''
        zstyle ':completion:*' matcher-list 'r:|=*' 'l:|=* r:|=* m:{a-z\-}={A-Z\_}'
        export LS_COLORS="$(vivid generate molokai)"
        zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
        # speed https://coderwall.com/p/9fksra/speed-up-your-zsh-completions
        zstyle ':completion:*' accept-exact '*(N)'
        zstyle ':completion:*' use-cache on
        zstyle ':completion:*' cache-path ~/.local/share/zsh/cache
        # menu if nb items > 2
        zstyle ':completion:*' menu select=2
        # preview directory's content with eza when completing cd
        zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
        # don't show fzf unless there are more than 4 items
        zstyle ':fzf-tab:*' ignore false 4
      '';
      initExtra = ''
        source ${pkgs.zsh-nix-shell}/share/zsh-nix-shell/nix-shell.plugin.zsh
        source ${pkgs.zsh-vi-mode}/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh
        source ${pkgs.zsh-history-substring-search}/share/zsh-history-substring-search/zsh-history-substring-search.zsh

        bindkey -v
        bindkey -M vicmd '^[[1;5C' emacs-forward-word
        bindkey -M vicmd '^[[1;5D' emacs-backward-word
        bindkey -M viins '^[[1;5C' emacs-forward-word
        bindkey -M viins '^[[1;5D' emacs-backward-word

        WORDCHARS=''${WORDCHARS//[\/&.;_-]}
        autoload -U select-word-style
        select-word-style bash
        bindkey '^W' backward-kill-word

        autoload -U up-line-or-beginning-search
        autoload -U down-line-or-beginning-search
        zle -N up-line-or-beginning-search
        zle -N down-line-or-beginning-search
        bindkey "$key[Up]" up-line-or-beginning-search
        bindkey "$key[Down]" down-line-or-beginning-search

        alias -g ...='../..'
        alias -g ....='../../..'
        alias -g .....='../../../..'
        alias -g ......='../../../../..'
        while read -r option
        do
          setopt $option
        done <<-EOF
        ALWAYS_TO_END
        EXTENDED_HISTORY
        HIST_EXPIRE_DUPS_FIRST
        HIST_FCNTL_LOCK
        HIST_IGNORE_ALL_DUPS
        HIST_IGNORE_DUPS
        HIST_IGNORE_SPACE
        HIST_REDUCE_BLANKS
        HIST_SAVE_NO_DUPS
        HIST_VERIFY
        SHARE_HISTORY
        EOF
      '';
    };
  };
  home.packages = with pkgs; [
    eza
    bottom
    bat
    fzf
    ripgrep
    rsync
    vivid
  ];
  home.global-persistence = {
    directories = [
      ".local/share/zsh"
    ];
  };
}
