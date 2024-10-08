{ pkgs, ... }:
let
  # https://github.com/finaldie/final_dev_env/blob/master/tmux
  remote_hostname = pkgs.writeText "hostname.sh" ''
    #!/usr/bin/env bash
    pane_tty=`tmux display -p "#{pane_tty}" | cut -d "/" -f3,4`
    target_host=`ps -af | awk -v ptty=$pane_tty '{if ($6 == ptty) print $0}' | grep -v grep | grep -oP "ssh [a-zA-Z0-9.@\-]+" | grep -vP "\ \-\w" | cut -d " " -f2 | grep -oP "(?=@*)[\w\d.\-]*" | tail -1`
    # echo "tty: $pane_tty , host: $target_host"
    echo $target_host
  '';
  nw_ttl = pkgs.writeText "nw_ttl.sh" ''
    #!/usr/bin/env bash
    target_host=`bash ${remote_hostname}`
    # echo "tty: $pane_tty , host: $target_host"
    ping -c 1 $target_host | tail -1 | cut -d "/" -f5
    # (ping -c 1 #(ps -af | grep "`tmux display -p \"#{pane_tty}\" | cut -d \"/\" -f3,4` " | grep -v grep | grep -oP "ssh [a-zA-Z0-9.@\-]+" | cut -d " " -f2 | grep -oP "(?=@*)[\w\d.\-]*" | tail -1) | tail -1 | cut -d "/" -f5)
  '';
in
{
  programs.tmux = {
    enable = true;
    baseIndex = 1;
    escapeTime = 10;
    shell = "${pkgs.zsh}/bin/zsh";
    keyMode = "vi";
    terminal = "tmux-256color";
    plugins = with pkgs; [
      tmuxPlugins.catppuccin
    ];
    extraConfig = ''
      # source: https://github.com/felixonmars/dotfiles/blob/master/.tmux.conf
      set -g prefix ^b
      set-option -gw xterm-keys on
      bind a send-prefix
      unbind '"'
      bind - splitw -v # 分割成上下两个窗口
      unbind %
      bind | splitw -h # 分割成左右两个窗口
      bind k selectp -U # 选择上窗格
      bind j selectp -D # 选择下窗格
      bind h selectp -L # 选择左窗格
      bind l selectp -R # 选择右窗格
      bind ^k resizep -U 10 # 跟选择窗格的设置相同，只是多加 Ctrl（Ctrl-k）
      bind ^j resizep -D 10 # 同上
      bind ^h resizep -L 10 # ...
      bind ^l resizep -R 10 # ...
      bind ^u swapp -U # 与上窗格交换 Ctrl-u
      bind ^d swapp -D # 与下窗格交换 Ctrl-d
      bind-key -n C-k clear-history
      bind m command-prompt "splitw -h 'exec man %%'"
      #bind @ command-prompt "splitw -h 'exec perldoc -f %%'"

      #set -g status-right "#[fg=green]#(uptime|sed -e's/.*up\s*\(.*min\).*/\1/')#[default] • #[fg=green]#(cut -d ' ' -f 1-3 /proc/loadavg)#[default]"
      #set -g status-right "#[fg=green]#(uptime|cut -d ' ' -f 4-7|cut -d ',' -f 1-2)#[default] • #[fg=green]#(cut -d ' ' -f 1-3 /proc/loadavg)#[default]"
      set -g status-right "#[fg=green]#[default] #[fg=green]#(bash ${remote_hostname} | cut -d "." -f1)#[default] #[fg=green]#(bash ${nw_ttl} | cut -d "." -f1)#[default] • #[fg=green]#(hostname | cut -d "." -f1)#[default]"
      #set -g status-right "#[fg=green]#[default] • #[fg=green]#(cut -d ' ' -f 1-3 /proc/loadavg)#[default]"
      #set -g status-right "#[fg=green]#(date) #[default]#(rainbarf)#[default]"
      # set -g status-bg black
      # set -g status-fg yellow
      # set -g status-style bg=colour0

      setw -g mode-keys vi
      #setw -g mode-mouse off
      #set -g mouse-select-pane on
      #setw -g mode-mouse on
      set-option -g mouse on
      #bind -t vi-copy WheelUpPane halfpage-up
      #bind -t vi-copy WheelDownPane halfpage-down

      set -g terminal-overrides 'rxvt*:smcup@:rmcup@'
      set -g base-index 1
      #set -s escape-time 0
      setw -g aggressive-resize on

      set -g update-environment "DISPLAY WINDOWID XAUTHORITY DBUS_SESSION_BUS_ADDRESS SESSION_MANAGER GNOME_KEYRING_CONTROL GPG_AGENT_INFO SSH_ASKPASS SSH_AUTH_SOCK SSH_AGENT_PID SSH_CONNECTION"
      #set -g update-environment ""

      set -g set-titles on
      setw -g automatic-rename

      unbind r
      bind r source-file ~/.config/tmux/tmux.conf

      set -g history-limit 50000

      #bind F 1 send-keys F1
      #bind F 2 send-keys F2
      bind Q send-keys F1
      bind W send-keys F2
      bind E send-keys F3
      bind R send-keys F4
      bind T send-keys F5
      bind Y send-keys F6
      bind U send-keys F7
      bind I send-keys F8
      bind O send-keys F9
      bind P send-keys F10
      bind A send-keys F11
      bind S send-keys F12

      bind / send-keys |

      unbind t
      bind t send-keys Tab

      unbind N
      bind N clock-mode

      unbind @
      bind @ send-keys Escape

      unbind H
      bind H send-keys Home

      unbind L
      bind L send-keys End

      unbind J
      bind J send-keys PageDown

      unbind K
      bind K send-keys PageUp

      #Alt-n window switching
      unbind M-1
      unbind M-2
      unbind M-3
      unbind M-4
      unbind M-5
      unbind M-6
      unbind M-7
      unbind M-8
      unbind M-9
      bind-key -n M-1 select-window -t :1
      bind-key -n M-2 select-window -t :2
      bind-key -n M-3 select-window -t :3
      bind-key -n M-4 select-window -t :4
      bind-key -n M-5 select-window -t :5
      bind-key -n M-6 select-window -t :6
      bind-key -n M-7 select-window -t :7
      bind-key -n M-8 select-window -t :8
      bind-key -n M-9 select-window -t :9
      bind-key -n M-q select-window -t :1 \; send-keys M-1
      bind-key -n M-w select-window -t :1 \; send-keys M-2
      bind-key -n M-e select-window -t :1 \; send-keys M-3
      bind-key -n M-r select-window -t :1 \; send-keys M-4
      bind-key -n M-t select-window -t :1 \; send-keys M-5
      bind-key -n M-y select-window -t :1 \; send-keys M-6
      bind-key -n M-u select-window -t :1 \; send-keys M-7
      bind-key -n M-i select-window -t :1 \; send-keys M-8
      bind-key -n M-o select-window -t :1 \; send-keys M-9

      bind-key -n C-q send-prefix

      bind-key -n ^PageDown next-window
      bind-key -n ^PageUp previous-window

      bind-key -n C-Tab next-window
      bind-key -n C-S-Tab previous-window

      #For more compatibility
      #set -g default-terminal "xterm-color"
      #set -as terminal-features ",xterm-256color:RGB"
      #set -ga terminal-overrides ",alacritty:Tc"
      set -as terminal-overrides ",xterm-256color:RGB"

      #set-option -g mouse-resize-pane on
      #set-option -g mouse-select-window on
      set-option -g set-clipboard on
      #set-option -g mouse-select-pane on

      bind-key u capture-pane \; save-buffer /tmp/tmux-buffer \; run-shell "$TERMINAL -e 'cat /tmp/tmux-buffer | urlview'"

      ##CLIPBOARD selection integration
      ##Requires prefix key before the command key
      #Copy tmux paste buffer to CLIPBOARD
      #bind C-c run -b "tmux show-buffer | xclip -i -selection clipboard"
      #bind C-c run -b "tmux show-buffer | wl-copy"
      bind C-c run -b "tmux show-buffer | autoclipboard copy"
      #Copy CLIPBOARD to tmux paste buffer and paste tmux paste buffer
      #bind C-v run "tmux set-buffer \"$(xclip -o -selection clipboard)\"; tmux paste-buffer"
      #bind C-v run "tmux set-buffer \"$(wl-paste)\"; tmux paste-buffer"
      bind C-v run "tmux set-buffer \"$(autoclipboard paste)\"; tmux paste-buffer"

      set -g status-position top
      set -g renumber-windows on
      set -g allow-passthrough on
      new-session -s main
    '';
  };
}
