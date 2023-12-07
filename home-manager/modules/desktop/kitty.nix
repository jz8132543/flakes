{pkgs, ...}: {
  programs.kitty = {
    enable = true;
    extraConfig = ''
      include ${pkgs.kitty-catppuccin}/mocha.conf
      font_size 12
      # background_opacity 0.6
      hide_window_decorations yes
      strip_trailing_spaces smart
      enable_audio_bell no
      shell tmux a
    '';
  };
}
