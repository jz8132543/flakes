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
      linux_display_server auto
      hide_window_decorations yes
      strip_trailing_spaces smart
      enable_audio_bell no
      shell tmux a
    '';
  };
}
