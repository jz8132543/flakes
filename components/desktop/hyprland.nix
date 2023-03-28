{ self, config, pkgs, lib, ... }:

{
  imports = [
    self.nixosModules.hyprland
  ];
  services = {
    logind.lidSwitch = "ignore";
    greetd = {
      enable = true;
      package = pkgs.greetd.tuigreet;
      settings = {
        default_session.command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd Hyprland";
      };
    };
  };
  programs.hyprland = {
    enable = true;
    xwayland = {
      enable = true;
      hidpi = true;
    };
    nvidiaPatches = false;
  };
  nix.settings = {
    substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];
  };

  environment.systemPackages = with pkgs; [
    hyprpaper
    wofi
    dunst
    swww
    eww-wayland
    swayidle
    swaylock-effects
    swaylock
    # sway-audio-idle-inhibit-git
    bc
    pamixer
    light
    papirus-icon-theme
    playerctl
    cava
    kitty
    xdg-desktop-portal-wlr
    grim
    slurp
    wl-clipboard
    socat
    swappy
    cliphist
    # hyprpicker
    # nm-connection-editor
    dict
    # wl-clip-persist-git
    blueberry
  ];
}
