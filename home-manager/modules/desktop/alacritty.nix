{
  pkgs,
  config,
  ...
}:
let
  alacrittyPackage = config.lib.self.wrapNoIme {
    inherit pkgs;
    pkg = pkgs.alacritty;
    extraArgs = "--set WINIT_UNIX_BACKEND x11";
  };
in
{
  programs = {
    alacritty = {
      enable = true;
      package = alacrittyPackage;
      settings = {
        colors = {
          primary = {
            background = "#1e1e1e";
            foreground = "#ffffff";
          };
          normal = {
            black = "#000000";
            red = "#ff5252";
            green = "#8bd64b";
            yellow = "#fdba2c";
            blue = "#46a1ff";
            magenta = "#ff81f2";
            cyan = "#13c9ce";
            white = "#e5e5e5";
          };
          bright = {
            black = "#545454";
            red = "#ff5252";
            green = "#8bd64b";
            yellow = "#fdba2c";
            blue = "#46a1ff";
            magenta = "#ff81f2";
            cyan = "#13c9ce";
            white = "#e5e5e5";
          };
        };
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
        bell = {
          duration = 0;
        };
      };
    };
  };
}
