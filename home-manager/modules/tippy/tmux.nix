{ pkgs, ... }:

{
  programs.tmux = {
    enable = true;
    baseIndex = 1;
    escapeTime = 10;
    shell = "${pkgs.zsh}/bin/zsh";
    keyMode = "vi";
    terminal = "screen-256color";
    plugins = with pkgs; [
      tmuxPlugins.better-mouse-mode
      tmuxPlugins.vim-tmux-navigator
      tmuxPlugins.gruvbox
      tmuxPlugins.tmux-fzf
    ];
    extraConfig = ''
      set -ga terminal-overrides ",*256col*:Tc"
      set -ga terminal-overrides '*:Ss=\E[%p1%d q:Se=\E[ q'
      set-environment -g COLORTERM "truecolor"

      set -g @plugin 'nhdaly/tmux-better-mouse-mode'
      set -g @plugin 'christoomey/vim-tmux-navigator'
      set -g @plugin 'sainnhe/tmux-fzf'
      set -g @plugin 'egel/tmux-gruvbox'
      set -g @tmux-gruvbox 'dark' # or 'light'

      set -g status-position bottom
      set -g set-clipboard on
      set -g mouse on
      set -g status-right ""
      set -g renumber-windows on
      new-session -s main
    '';
  };
}

