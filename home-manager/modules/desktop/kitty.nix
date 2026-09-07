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
    font = {
      name = "JetBrainsMono Nerd Font";
      size = 15;
    };
    extraConfig = ''
      # 始终保持连字开启（即使光标在上面也不拆开）
      disable_ligatures never

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
      # background_opacity 0.6
      # Native Wayland under GNOME for zero startup/focus latency
      linux_display_server wayland
      wayland_enable_ime no
      hide_window_decorations yes
      strip_trailing_spaces smart
      enable_audio_bell no
      notify_on_cmd_finish never
      shell tmux a
    '';
  };
}
