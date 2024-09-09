{
  pkgs,
  config,
  ...
}:
{
  programs = {
    alacritty = {
      enable = true;
      settings = {
        import = [ "${pkgs.alacritty-catppuccin}/catppuccin-mocha.toml" ];
        shell = {
          program = "${pkgs.tmux}/bin/tmux";
          args = [ "a" ];
        };
        font = {
          normal.family = "JetBrainsMono Nerd Font Mono";
          italic.family = "JetBrainsMono Nerd Font Mono";
          bold_italic.family = "JetBrainsMono Nerd Font Mono";
          bold.family = "JetBrainsMono Nerd Font Mono";
          size = 15 * config.wayland.dpi / 96;
        };
        window = {
          # opacity = 0.8;
          decorations = "none";
        };
        env.TERM = "xterm-256color";
      };
    };
  };
}
