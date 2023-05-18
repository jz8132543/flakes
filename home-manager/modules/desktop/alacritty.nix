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
        # import = [ ./alacritty.yml ];
        font = {size = 14.0;};
        shell = {
          program = "${pkgs.tmux}/bin/tmux";
          args = ["new-session" "-t" "main"];
        };
        window.opacity = 0.8;
      };
    };
  };
  home.persistence."/nix/persist/home/tippy" = {
    directories = [
      ".local/share/TelegramDesktop"
      ".thunderbird"
    ];
  };
}
