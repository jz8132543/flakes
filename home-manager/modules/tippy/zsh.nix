{ pkgs, ... }:
{
  programs.starship = {
    enable = true;
  };
  programs.zoxide.enable = true;
  programs.zsh = {
    enable = true;
    history.path = "$HOME/.local/share/zsh/zsh_history";
    dotDir = ".config/zsh";
    defaultKeymap = "emacs";

    enableVteIntegration = true;
    enableAutosuggestions = true;
    enableCompletion = true;
    autocd = true;

    initExtra = ''
      source ${pkgs.zsh-nix-shell}/share/zsh-nix-shell/nix-shell.plugin.zsh
      source ${pkgs.zsh-vi-mode}/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh
      source ${pkgs.zsh-fast-syntax-highlighting}/share/zsh/site-functions/fast-syntax-highlighting.plugin.zsh
      bindkey "^[[1;5C" forward-word
      bindkey "^[[1;5D" backward-word
      autoload -U select-word-style
      select-word-style bash
      WORDCHARS='*?_-.[]~=&;!#$%^(){}<>'
      bindkey "^W" backward-kill-word
    '';
    shellAliases = {
      ls = "${pkgs.exa}/bin/exa --icons";
      tree = "${pkgs.exa}/bin/exa --tree --icons";
      top = "${pkgs.bottom}/bin/btm";
      cat = "${pkgs.bat}/bin/bat --style=plain";
      fzf =
        "${pkgs.fzf}/bin/fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}'";
      batdiff =
        "git diff --name-only --relative --diff-filter=d | xargs ${pkgs.bat}/bin/bat --diff";
      rg = "${pkgs.ripgrep}/bin/rg --no-ignore";
    };
  };
  home.persistence."/nix/persist/home/tippy" = {
    directories = [
      ".local/share/zsh"
    ];
  };
}
