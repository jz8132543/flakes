{...}: {
  programs.kitty = {
    enable = true;
    font = {
      name = "JetbrainMono Nerd Font";
      size = 15;
    };
    extraConfig = ''
      background_opacity 0.6
      hide_window_decorations yes
      strip_trailing_spaces smart
      enable_audio_bell no
      shell tmux a
    '';
  };
}
