{ pkgs, ... }:

{
  programs = {
    rofi = {
      enable = true;
      plugins = [
        pkgs.rofi-emoji
        pkgs.rofi-calc
        pkgs.rofi-power-menu
      ];
      extraConfig = {
        modi = "drun";
        show-icons = true;
        sort = true;
        # matching = "fuzzy";
      };
      theme = "rounded-blue-dark.rasi";
    };
  };
  home.file.".config/rofi/rounded-blue-dark.rasi".source = ./rounded-blue-dark.rasi;
}
