{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    lutris
    # heroic
    wineWowPackages.staging
    winetricks
  ];
  environment.global-persistence.user.directories = [
    "Games"
    ".local/share/lutris"
    # ".config/heroic"
  ];
}
