{...}: {
  programs.kitty = {
    enable = true;
    extraConfig = ''
      font_size 15
      background_opacity 0.6
      hide_window_decorations yes
      strip_trailing_spaces smart
      enable_audio_bell no
      shell tmux a
    '';
  };
}
