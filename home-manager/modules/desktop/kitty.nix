{
  pkgs,
  config,
  ...
}: {
  programs.kitty = {
    enable = true;
    extraConfig = ''
      include ${pkgs.kitty-catppuccin}/mocha.conf
      font_size ${toString (12 * config.wayland.dpi / 96)}
      # background_opacity 0.6
      # TODO
      linux_display_server x11
      hide_window_decorations yes
      strip_trailing_spaces smart
      enable_audio_bell no
      # shell tmux a
    '';
  };
}
