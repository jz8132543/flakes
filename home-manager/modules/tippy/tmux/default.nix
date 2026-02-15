# https://github.com/Veraticus/nix-config/blob/b05c349029ecfe990d431fbf99a9af4c86b166f1/home-manager/tmux/default.nix
{
  pkgs,
  ...
}:
let
  # tmuxDevspaceHelper = pkgs.writeShellScriptBin "tmux-devspace" (
  #   builtins.readFile ./tmux-devspace.sh
  # );
  # 1. 定义工具路径
  tcping = "${pkgs.tcping-rs}/bin/tcping";
  ssh = "${pkgs.openssh}/bin/ssh";
  tmux-net-speed = pkgs.writeShellScriptBin "tmux-net-speed" ''
    export PATH="${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gawk}/bin:${pkgs.procps}/bin:$PATH"
    STATE_FILE="/tmp/tmux-net-speed-$USER"
    read rx_now tx_now < <(awk 'NR > 2 && $1 !~ /lo:/ {rx += $2; tx += $10} END {print rx, tx}' /proc/net/dev)
    if [ -f "$STATE_FILE" ]; then
        read rx_old tx_old ts_old < "$STATE_FILE"
    else
        rx_old=$rx_now; tx_old=$tx_now; ts_old=$(date +%s)
    fi
    ts_now=$(date +%s); dt=$((ts_now - ts_old)); [ "$dt" -le 0 ] && dt=1
    echo "$rx_now $tx_now $ts_now" > "$STATE_FILE"
    format_speed() {
        local s=$(( ($1) / $2 ))
        if [ "$s" -ge 1048576 ]; then echo "$((s / 1048576)) MB/s"
        elif [ "$s" -ge 1024 ]; then echo "$((s / 1024)) KB/s"
        else echo "$s B/s"; fi
    }
    printf "↓%s ↑%s" "$(format_speed $((rx_now - rx_old)) $dt)" "$(format_speed $((tx_now - tx_old)) $dt)"
  '';
  tmux-ssh-status = pkgs.writeShellScriptBin "tmux-ssh-status" ''
    tty=$1
    export PATH="${pkgs.procps}/bin:${pkgs.gnugrep}/bin:${pkgs.gawk}/bin:${pkgs.coreutils}/bin:${pkgs.nettools}/bin:${pkgs.gnused}/bin:$PATH"

    # --- Catppuccin Mocha 配色 (Lavender) ---
    COLOR_ICON_BG="#b4befe"
    COLOR_ICON_FG="#11111b"
    COLOR_TEXT_BG="#313244"
    COLOR_TEXT_FG="#cdd6f4"

    # 1. 默认状态：显示本地主机名
    ICON="  "
    display_text=$(hostname)

    # 2. 获取进程 (使用 ps -e 配合 awk 匹配 TTY，解决 NixOS/Fish 下抓不到进程的问题)
    tty_clean=''${tty#/dev/}
    raw_cmd=$(ps -e -o tty,args= | awk -v t="$tty_clean" '$1 == t { $1=""; print $0 }' | grep "ssh" | grep -v "tmux-ssh-status" | head -n 1)

    if [ -n "$raw_cmd" ]; then
      ICON="  "

      # 3. 提取显示用的别名 (Alias) - 用于状态栏显示
      target_alias=$(echo "$raw_cmd" | \
        sed -E 's/^.*ssh\s+//' | \
        sed -E 's/ -[a-zA-Z0-9] [^ ]+ / /g' | \
        sed -E 's/ -[a-zA-Z0-9] / /g' | \
        awk '{print $1}' | \
        cut -d@ -f2)

      display_text="$target_alias"

      # 4. 提取真实连接参数 - 用于 ssh -G 解析
      # 去除 /nix/store/.../ssh 前缀，只保留参数
      pure_args=$(echo "$raw_cmd" | sed -E 's/^.*ssh\s+//')

      ssh_config=$(${ssh} -G $pure_args 2>/dev/null)
      config_host=$(echo "$ssh_config" | awk '/^hostname / {print $2}')
      config_port=$(echo "$ssh_config" | awk '/^port / {print $2}')

      # 优先使用命令行指定的端口
      explicit_port=$(echo "$raw_cmd" | grep -oE " -p ?[0-9]+" | sed 's/[^0-9]*//g' | head -n 1)

      final_host="$config_host"
      if [ -n "$explicit_port" ]; then
        final_port="$explicit_port"
      else
        final_port="$config_port"
      fi

      # 5. 执行延迟测试
      if [ -n "$final_host" ] && [ -n "$final_port" ]; then
         # 使用你确认过的参数: --timeout-ms 500 和 host:port
         tcping_out=$(${tcping} -c 1 --timeout-ms 500 "$final_host":"$final_port" 2>&1)

         # 提取 " - open - " 前面的数字
         latency=$(echo "$tcping_out" | awk '/ - open - / {print $(NF-1)}' | cut -d. -f1)

         if [ -n "$latency" ]; then
           display_text="$target_alias $latency"
         fi
      fi
    fi

    # 输出 Catppuccin 风格的状态栏组件
    echo "#[fg=''${COLOR_ICON_BG}]#{E:@catppuccin_status_left_separator}#[fg=''${COLOR_ICON_FG},bg=''${COLOR_ICON_BG}]''${ICON}#{E:@catppuccin_status_middle_separator}#[fg=''${COLOR_TEXT_FG},bg=''${COLOR_TEXT_BG}] $display_text#[fg=''${COLOR_TEXT_BG}]#{E:@catppuccin_status_right_separator}"
  '';
in
{
  programs.tmux = {
    enable = true;
    baseIndex = 1;
    historyLimit = 200000;
    keyMode = "vi";
    mouse = true;
    escapeTime = 0;
    terminal = "tmux-256color";

    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      {
        plugin = net-speed;
        extraConfig = ''
          set -g @download_speed_format "%8s"
          set -g @upload_speed_format "%8s"
          set -g @net_speed_format "↓%s ↑%s"
        '';
      }
      {
        plugin = cpu;
        extraConfig = ''
          set -g @cpu_percentage_format "%3d%%"
          set -g @ram_percentage_format "%2d%%"
        '';
      }
      {
        plugin = catppuccin;
        extraConfig = ''
          # Catppuccin settings
          set -g @catppuccin_flavor 'mocha'
          set -g @catppuccin_window_status_style "rounded"

          # Ensure transparent backgrounds where possible
          set -g status-bg default
          set -g message-style "fg=#94e2d5,bg=default"
          set -g message-command-style "fg=#94e2d5,bg=default"

          # Window settings
          set -g @catppuccin_window_left_separator ""
          set -g @catppuccin_window_right_separator " "
          set -g @catppuccin_window_middle_separator " █"
          set -g @catppuccin_window_number_position "right"

          set -g @catppuccin_window_default_fill "number"
          set -g @catppuccin_window_default_text "#{window_name}"

          set -g @catppuccin_window_current_fill "number"
          set -g @catppuccin_window_current_text "#{window_name}"
        '';
      }
    ];

    extraConfig = ''
      # Enable true color support
      set -ga terminal-overrides ",tmux-256color:Tc"
      set -ga terminal-overrides ",xterm-256color:Tc"
      set -ga terminal-overrides ",xterm-kitty:Tc"
      # Eternal Terminal presents itself as a screen(1) derivative, so make
      # sure tmux still drives it with truecolor sequences.
      set -ga terminal-overrides ",screen-256color:Tc"
      set -ga terminal-overrides ",screen:Tc"
      set -as terminal-features ",tmux-256color:RGB"
      set -as terminal-features ",xterm-256color:RGB"
      set -as terminal-features ",xterm-kitty:RGB"
      set -as terminal-features ",screen-256color:RGB"
      set -as terminal-features ",screen:RGB"

      # Ensure proper color rendering
      set -g default-terminal "tmux-256color"
      set -ag terminal-overrides ",xterm*:RGB"
      set -ag terminal-overrides ",screen*:RGB"

      # Allow TUIs to detect terminal capabilities accurately
      set -ga update-environment "COLORTERM"
      set -ga update-environment "TERM_PROGRAM"
      set -ga update-environment "TERM_PROGRAM_VERSION"
      set -g allow-passthrough on
      set -g set-clipboard on

      # General Settings
      setw -g pane-base-index 1
      set -g renumber-windows on
      set -g set-titles on
      set -g focus-events on
      set -g status-position bottom
      setw -g automatic-rename on
      setw -g allow-rename on
      set -g automatic-rename-format '#{pane_current_command}'

      # Status line configuration
      set -g status-right-length 100
      set -g status-left-length 100
      set -g status-left ""

      # Right side status with system monitoring
      set -g status-interval 3

      set -g status-right \
        "#(${tmux-ssh-status}/bin/tmux-ssh-status #{pane_tty})"

      set -ag status-right \
        "#[fg=#94e2d5]#{E:@catppuccin_status_left_separator}#[fg=#11111b,bg=#94e2d5]󰓅  #{E:@catppuccin_status_middle_separator}#[fg=#cdd6f4,bg=#313244] #(${tmux-net-speed}/bin/tmux-net-speed)#[fg=#313244]#{E:@catppuccin_status_right_separator}"

      set -ag status-right \
        "#[fg=#f9e2af]#{E:@catppuccin_status_left_separator}#[fg=#11111b,bg=#f9e2af]#{E:@catppuccin_cpu_icon} #{E:@catppuccin_status_middle_separator}#[fg=#cdd6f4,bg=#313244] #(${pkgs.tmuxPlugins.cpu}/share/tmux-plugins/cpu/scripts/cpu_percentage.sh)#[fg=#313244]#{E:@catppuccin_status_right_separator}"

      set -g @catppuccin_ram_icon " "

      set -ag status-right \
        "#[fg=#cba6f7]#{E:@catppuccin_status_left_separator}#[fg=#11111b,bg=#cba6f7]  #{E:@catppuccin_status_middle_separator}#[fg=#cdd6f4,bg=#313244] #(${pkgs.tmuxPlugins.cpu}/share/tmux-plugins/cpu/scripts/ram_percentage.sh)#[fg=#313244]#{E:@catppuccin_status_right_separator}"

      # Pane borders - Catppuccin Mocha colors
      set -g pane-border-style "fg=#313244"
      set -g pane-active-border-style "fg=#89b4fa"

      # Window and pane styles - ensure no background is set
      set -g window-style 'default'
      set -g window-active-style 'default'

      # Key bindings
      # unbind C-b
      # set -g prefix C-a
      # bind C-a send-prefix

      # Window/pane creation with current path
      bind c new-window -c "#{pane_current_path}"
      bind '"' split-window -c "#{pane_current_path}"
      bind % split-window -h -c "#{pane_current_path}"

      # Smart mouse wheel behavior - scroll alternate screen apps naturally
      bind -n WheelUpPane if -F "#{pane_in_mode}" "send-keys -M" "if -F '#{alternate_on}' 'send-keys -M' 'copy-mode -e; send-keys -M'"
      bind -n WheelDownPane if -F "#{pane_in_mode}" "send-keys -M" "send-keys -M"

      # Vim-style pane navigation
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R

      # Quick window switching
      bind-key -n M-1 select-window -t 1
      bind-key -n M-2 select-window -t 2
      bind-key -n M-3 select-window -t 3
      bind-key -n M-4 select-window -t 4
      bind-key -n M-5 select-window -t 5

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
      unbind r
      bind r source-file ~/.config/tmux/tmux.conf
      set-option -g set-clipboard on
      bind-key u capture-pane \; save-buffer /tmp/tmux-buffer \; run-shell "$TERMINAL -e 'cat /tmp/tmux-buffer | urlview'"
      bind C-c run -b "tmux show-buffer | autoclipboard copy"
      bind C-v run "tmux set-buffer \"$(autoclipboard paste)\"; tmux paste-buffer"
      set -g status-position top
      set -g renumber-windows on
      set -g allow-passthrough on
      new-session -s main
    '';
  };
  home.packages = with pkgs; [
    tcping-rs
  ];
}
