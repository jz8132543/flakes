{
  pkgs,
  osConfig,
  config,
  lib,
  ...
}:
let
  catppuccin = pkgs.catppuccin.override {
    inherit (config.home.catppuccin) variant;
    inherit (config.home.catppuccin) accent;
  };
  # 统一维护 fish / zsh 共用的命令别名，避免两边行为慢慢漂移。
  sharedShellAliases = {
    # 资源监控：bottom 在窄终端里也比 htop 更易读。
    top = "${pkgs.bottom}/bin/btm --enable_cache_memory --battery";

    # 文本查看：统一走 bat，保持语法高亮与主题风格一致。
    cat = "${pkgs.bat}/bin/bat --style=plain";
    fzf = "${pkgs.fzf}/bin/fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}'";
    batdiff = "git diff --name-only --relative --diff-filter=d | xargs ${pkgs.bat}/bin/bat --diff";
    rg = "${pkgs.ripgrep}/bin/rg --no-ignore";

    # 文件浏览：保留原生 ls，额外提供一组稳定的 eza 快捷方式。
    l = "${pkgs.eza}/bin/eza --icons=auto --group-directories-first";
    ll = "${pkgs.eza}/bin/eza --icons=auto --group-directories-first -lh";
    la = "${pkgs.eza}/bin/eza --icons=auto --group-directories-first -lah";
    lt = "${pkgs.eza}/bin/eza --icons=auto --tree --level=2";

    # 常用工具：给常用参数提供安全默认值，减少重复输入。
    rsync = "${pkgs.rsync}/bin/rsync -arvzP";
    sl = "journalctl --unit";
  };
  toTitle =
    str: "${lib.toUpper (lib.substring 0 1 str)}${lib.substring 1 (lib.stringLength str) str}";
  inherit (config.home.catppuccin) flavor;
in
{
  programs = {
    fish = {
      enable = true;
      shellAliases = sharedShellAliases;
      shellAbbrs = {
        # 交互命令优先用 abbr，仍允许你在需要时退回原始命令。
        diff = "batdiff";
        less = "batpipe";
        man = "batman";
      };
      interactiveShellInit = lib.mkMerge [
        (lib.mkBefore ''
          set -g fish_escape_delay_ms 300
          set -g fish_greeting
        '')
        (lib.mkAfter ''
          ${pkgs.nix-your-shell}/bin/nix-your-shell --nom fish | source
          # Make Ctrl+W treat host separators like '@' and '.' as word boundaries.
          if not string match -q '*@*' -- $fish_word_delimiters
            set -g fish_word_delimiters "$fish_word_delimiters@"
          end
          if not string match -q '*.*' -- $fish_word_delimiters
            set -g fish_word_delimiters "$fish_word_delimiters."
          end
          fish_vi_key_bindings insert
          # quickly open text file
          bind -M insert \co 'fzf | xargs -r $EDITOR'
          bind -M insert \ca beginning-of-line
          bind -M insert \cw backward-kill-word
          # Ctrl+←/→ jump by fish_word_delimiters (includes '@' and '.')
          bind -M insert \e\[1\;5D backward-word
          bind -M insert \e\[1\;5C forward-word
          bind -M insert \e\[5D backward-word
          bind -M insert \e\[5C forward-word
          bind -M default \cw backward-kill-word
          bind -M default \e\[1\;5D backward-word
          bind -M default \e\[1\;5C forward-word
          bind -M default \e\[5D backward-word
          bind -M default \e\[5C forward-word
        '')
      ];
    };
    zsh = {
      enable = true;
      history.path = "$HOME/.local/share/zsh/zsh_history";
      dotDir = "${config.xdg.configHome}/zsh";
      defaultKeymap = "emacs";

      enableVteIntegration = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      autocd = true;
      enableCompletion = true;

      shellAliases = sharedShellAliases;
      initContent = lib.mkOrder 550 ''
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

        # 目录跳转保留为 zsh 原生 alias，输入成本最低。
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
    starship = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      enableFishIntegration = true;
      settings = {
        # git
        git_commit.commit_hash_length = 7;
        git_branch.style = "bold purple";
        git_status = {
          style = "red";
          ahead = "⇡ ";
          behind = "⇣ ";
          conflicted = " ";
          renamed = "»";
          deleted = "✘ ";
          diverged = "⇆ ";
          modified = "!";
          stashed = "≡";
          staged = "+";
          untracked = "?";
        };
        # language configurations
        # the whitespaces at the end *are* necessary for proper formatting
        python.symbol = "[ ](blue) ";
        rust.symbol = "[ ](red) ";
        nix_shell.symbol = "[󱄅 ](blue) ";
        golang.symbol = "[󰟓 ](blue)";
        package.disabled = true;
        # palette = "catppuccin_${flavor}";
      };
      # // builtins.fromTOML (builtins.readFile "${catppuccin}/starship/${flavor}.toml");
    };
    atuin = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      enableFishIntegration = true;
      flags = [
        "--disable-up-arrow"
        # "--disable-ctrl-r"
      ];

      settings = {
        sync_address = "https://atuin.${osConfig.networking.domain}";
        sync_frequency = "1m";
        dialect = "uk";
        enter_accept = false;
        records = true;
        show_preview = true;
        # skim = fuzzy match (relevance first), prefix = prefix match (time first)
        # fuzzy = fuzzy match but sorted by time
        search_mode = "fuzzy";
        history_ignore = [ "^ " ];
        inline_height = 20;
      };
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
      enableFishIntegration = true;
      git = true;
      icons = "auto";
    };
    bat = {
      enable = true;
      config = {
        pager = "less -FR";
        theme = "catppuccin-${flavor}";
      };
      themes = {
        "catppuccin-${config.home.catppuccin.flavor}" = {
          src = catppuccin;
          file = "bat/Catppuccin\ ${toTitle flavor}.tmTheme";
        };
      };
      extraPackages = with pkgs.bat-extras; [
        batman
        batgrep
        batwatch
        batpipe
        batdiff
      ];
    };
    bottom = {
      settings = { } // builtins.fromTOML (builtins.readFile "${catppuccin}/bottom/${flavor}.toml");
    };
    skim.enable = true;
  };
  home.packages =
    with pkgs;
    [
      eza
      bottom
      bat
      fzf
      ripgrep
      rsync
      vivid

      # Fish plugins from NixOS
      fishPlugins.autopair-fish
      fishPlugins.done
      fishPlugins.fish-you-should-use
      fishPlugins.foreign-env
      fishPlugins.forgit
      fishPlugins.puffer
      # nur.repos.linyinfeng.fishPlugins.replay
      libnotify # for done notification
    ]
    ++ lib.optional (pkgs ? comma-with-db) pkgs.comma-with-db;
  home.global-persistence = {
    directories = [
      ".local/share/zsh"
      ".local/share/zoxide"
      ".local/share/direnv"
      ".local/share/fish"
      ".local/share/atuin"
    ];
  };
}
