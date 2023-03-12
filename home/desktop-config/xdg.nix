{ nixosConfig, config, lib, pkgs, ... }:

{
  xdg = {
    enable = true;
    userDirs = {
      enable = true;
      createDirectories = false;
      desktop = "$HOME/.local/XDG/Desktop";
      documents = "$HOME/.local/XDG/Documents";
      download = "$HOME/.local/XDG/Downloads";
      templates = "$HOME/.local/XDG/Templates";
      music = "$HOME/.local/XDG/Music";
      videos = "$HOME/.local/XDG/Videos";
      pictures = "$HOME/.local/XDG/Pictures";
      publicShare = "$HOME/.local/XDG/Public";
    };
  };
  home.persistence."/nix/persist/home/tippy" = {
    directories = [
      ".local/XDG"
    ];
  };
}
