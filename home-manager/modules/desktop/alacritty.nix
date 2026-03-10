{
  pkgs,
  config,
  ...
}:
let
  alacrittyPackage = pkgs.symlinkJoin {
    name = "alacritty-x11";
    paths = [ pkgs.alacritty ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/alacritty \
        --set WINIT_UNIX_BACKEND x11
    '';
  };
in
{
  programs = {
    alacritty = {
      enable = true;
      package = alacrittyPackage;
      settings = {
        general.import = [ "${pkgs.alacritty-catppuccin}/catppuccin-mocha.toml" ];
        terminal.shell = {
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
        env = {
          TERM = "xterm-256color";
        };
      };
    };
  };
}
