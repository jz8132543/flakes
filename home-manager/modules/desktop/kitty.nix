{
  pkgs,
  config,
  ...
}:
{
  programs.kitty = {
    enable = true;
    package = pkgs.symlinkJoin {
      name = "kitty-terminal-english";
      paths = [ pkgs.kitty ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/kitty \
          --set GTK_IM_MODULE xim \
          --set QT_IM_MODULE xim \
          --set SDL_IM_MODULE xim \
          --set XMODIFIERS @im=none \
          --unset XIM
      '';
    };
    extraConfig = ''
      include ${pkgs.kitty-catppuccin}/mocha.conf
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
      shell tmux a
    '';
  };
}
