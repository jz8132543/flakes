{ pkgs, ... }:

{
  programs.tmux = {
    enable = true;
    baseIndex = 1;
    escapeTime = 10;
    shell = "${pkgs.zsh}/bin/zsh";
    keyMode = "vi";
    terminal = "screen-256color";
    extraConfig = ''
      # https://old.reddit.com/r/tmux/comments/mesrci/tmux_2_doesnt_seem_to_use_256_colors/
      set -ga terminal-overrides ",*256col*:Tc"
      set -ga terminal-overrides '*:Ss=\E[%p1%d q:Se=\E[ q'
      set-environment -g COLORTERM "truecolor"

      set -g status-position top
      set -g set-clipboard on
      set -g mouse on
      set -g status-right ""
      set -g renumber-windows on
      new-session -s main

      # Color Scheme
      # window status style
#   - built-in variables are:
#     - #{circled_window_index}
#     - #{circled_session_name}
#     - #{hostname}
#     - #{hostname_ssh}
#     - #{hostname_full}
#     - #{hostname_full_ssh}
#     - #{username}
#     - #{username_ssh}
tmux_conf_theme_window_status_fg=$nord5             
tmux_conf_theme_window_status_bg=$nord1              
tmux_conf_theme_window_status_attr="none"
tmux_conf_theme_window_status_format="#I #W"

# window current status style
#   - built-in variables are:
#     - #{circled_window_index}
#     - #{circled_session_name}
#     - #{hostname}
#     - #{hostname_ssh}
#     - #{hostname_full}
#     - #{hostname_full_ssh}
#     - #{username}
#     - #{username_ssh}
#   ﲵ            ﮊ ﮏ ♥ ﰸ ﯅  
tmux_conf_theme_window_status_current_fg=$nord6      
tmux_conf_theme_window_status_current_bg=$nord10 
tmux_conf_theme_window_status_current_attr="bold"
tmux_conf_theme_window_status_current_format=" #W"

# window activity status style
tmux_conf_theme_window_status_activity_fg="default"
tmux_conf_theme_window_status_activity_bg="default"
tmux_conf_theme_window_status_activity_attr="underscore"

# window bell status style
tmux_conf_theme_window_status_bell_fg='#ffff00' 
tmux_conf_theme_window_status_bell_bg="default"
tmux_conf_theme_window_status_bell_attr="blink,bold"

# window last status style
tmux_conf_theme_window_status_last_fg="default"
tmux_conf_theme_window_status_last_bg="default"
tmux_conf_theme_window_status_last_attr="none"
tmux_conf_theme_window_status_last_format='#I #W-'

# status left/right content:
#   - separate main sections with "|"
#   - separate subsections with ","
#   - built-in variables are:
#     - #{battery_bar}
#     - #{battery_hbar}
#     - #{battery_percentage}
#     - #{battery_status}
#     - #{battery_vbar}
#     - #{circled_session_name}
#     - #{hostname_ssh}
#     - #{hostname}
#     - #{hostname_full}
#     - #{hostname_full_ssh}
#     - #{loadavg}
#     - #{mouse}
#     - #{pairing}
#     - #{prefix}
#     - #{root}
#     - #{synchronized}
#     - #{uptime_y}
#     - #{uptime_d} (modulo 365 when #{uptime_y} is used)
#     - #{uptime_h}
#     - #{uptime_m}
#     - #{uptime_s}
#     - #{username}
#     - #{username_ssh}
tmux_conf_theme_status_left="  #S "
#tmux_conf_theme_status_right="#{prefix}#{mouse}#{pairing}#{synchronized}#{?battery_status,#{battery_status},}#{?battery_bar, #{battery_bar},}#{?battery_percentage, #{battery_percentage},} , %R , %d %b | #{username}#{root} | #{hostname} "
tmux_conf_theme_status_right='#{prefix}#{pairing}#{synchronized}#{?battery_bar, #{battery_bar},}#{?battery_percentage, #{battery_percentage},}#{?battery_status,#{battery_status},} | %b %d | %R | 
tmux_conf_theme_status_left_fg=$nord5 # '#e4e4e4,#e4e4e4,#e4e4e4'  # black, white , white
tmux_conf_theme_status_left_bg=$nord0 #',#00afff'  # yellow, pink, white blue
tmux_conf_theme_status_left_attr='bold,none,none'

# status right style
#tmux_conf_theme_status_right_fg="$tmux_conf_theme_colour_12,$tmux_conf_theme_colour_13,$tmux_conf_theme_colour_14"
#tmux_conf_theme_status_right_bg="$tmux_conf_theme_colour_15,$tmux_conf_theme_colour_16,$tmux_conf_theme_colour_17"
tmux_conf_theme_status_right_fg=$nord4,$nord6,$nord6,$nord5,$nord5
tmux_conf_theme_status_right_bg=$nord1,$nord7,$nord10,$nord2,$nord1 # dark gray, red, white
tmux_conf_theme_status_right_attr='bold,none,bold,none,none,none'
    '';
  };
}
