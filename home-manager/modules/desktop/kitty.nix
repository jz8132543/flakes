{
  pkgs,
  config,
  ...
}:
{
  programs.kitty = {
    enable = true;
    extraConfig = ''
      include ${pkgs.kitty-catppuccin}/mocha.conf
      # font_size ${toString (15 * config.wayland.dpi / 96)}
      font_size 15
      # background_opacity 0.6
      # Force X11/XWayland under GNOME so fcitx5 can keep a separate input
      # context for kitty and the terminal-only English group can match.
      linux_display_server x11
      hide_window_decorations yes
      strip_trailing_spaces smart
      enable_audio_bell no
      shell tmux a
    '';
  };
}
