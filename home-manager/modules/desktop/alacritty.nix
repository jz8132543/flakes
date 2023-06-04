{
  nixosConfig,
  config,
  lib,
  pkgs,
  ...
}: {
  programs = {
    alacritty = {
      enable = true;
      settings = {
        shell = {
          program = "${pkgs.tmux}/bin/tmux";
          args = ["new-session" "-t" "main"];
        };
        font = {
          size = 15.0;
        };
        window = {
          opacity = 0.8;
          decorations = "none";
        };
        env.TERM = "xterm-256color";
      };
    };
  };
}
