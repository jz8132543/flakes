{pkgs, ...}: {
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    enableFishIntegration = true;
  };
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    enableFishIntegration = true;
    tmux.enableShellIntegration = true;
  };
  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    enableFishIntegration = true;
  };
  programs.zsh = {
    enable = true;
    history.path = "$HOME/.local/share/zsh/zsh_history";
    dotDir = ".config/zsh";
    defaultKeymap = "emacs";

    enableVteIntegration = true;
    enableAutosuggestions = true;
    enableCompletion = true;
    enableSyntaxHighlighting = true;
    autocd = true;

    shellAliases = {
      ls = "${pkgs.exa}/bin/exa --icons";
      tree = "${pkgs.exa}/bin/exa --tree --icons";
      top = "${pkgs.bottom}/bin/btm";
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
      # preview directory's content with exa when completing cd
      zstyle ':fzf-tab:complete:cd:*' fzf-preview 'exa -1 --color=always $realpath'
      # don't show fzf unless there are more than 4 items
      zstyle ':fzf-tab:*' ignore false 4
    '';
    initExtra = ''
      source ${pkgs.zsh-nix-shell}/share/zsh-nix-shell/nix-shell.plugin.zsh
      source ${pkgs.zsh-vi-mode}/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh

      bindkey -v
      bindkey -M vicmd '^[[1;5C' emacs-forward-word
      bindkey -M vicmd '^[[1;5D' emacs-backward-word
      bindkey -M viins '^[[1;5C' emacs-forward-word
      bindkey -M viins '^[[1;5D' emacs-backward-word

      WORDCHARS=''${WORDCHARS//[\/&.;_-]}
      autoload -U select-word-style
      select-word-style bash
      bindkey '^W' backward-kill-word
      bindkey "^[[A" history-beginning-search-backward
      bindkey "^[[B" history-beginning-search-forward
      alias -g ...='../..'
      alias -g ....='../../..'
      alias -g .....='../../../..'
      alias -g ......='../../../../..'
    '';
  };
  home.packages = with pkgs; [
    exa
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
