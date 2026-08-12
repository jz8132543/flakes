{
  pkgs,
  config,
  ...
}:
{
  programs.kitty = {
    enable = true;
    package = config.lib.self.wrapNoIme {
      inherit pkgs;
      pkg = pkgs.kitty;
    };
    extraConfig = ''
      # macOS Terminal Dark Theme
      background #1e1e1e
      foreground #ffffff
      cursor #9d9e9e
      selection_background #3e5a7b
      color0 #000000
      color8 #545454
      color1 #ff5252
      color9 #ff5252
      color2 #8bd64b
      color10 #8bd64b
      color3 #fdba2c
      color11 #fdba2c
      color4 #46a1ff
      color12 #46a1ff
      color5 #ff81f2
      color13 #ff81f2
      color6 #13c9ce
      color14 #13c9ce
      color7 #e5e5e5
      color15 #e5e5e5
      selection_foreground #ffffff
      # font_size ${toString (15 * config.wayland.dpi / 96)}
      font_size 15
      # background_opacity 0.6
      # Force X11/XWayland under GNOME. Native GNOME Wayland IM integration uses
      # the compositor/text-input path, where fcitx5 cannot reliably keep a
      # distinct per-window state for third-party IMEs.
      linux_display_server x11
      wayland_enable_ime no
      hide_window_decorations yes
      strip_trailing_spaces smart
      enable_audio_bell no
      notify_on_cmd_finish never
      shell tmux a
    '';
  };
}
