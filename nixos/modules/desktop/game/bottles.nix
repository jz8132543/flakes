{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    bottles
    wineWowPackages.staging
    winetricks
    protonplus # Blog recommendation: Manage compatibility layers
    protonup-qt # Common native tool to manage Proton/Wine versions
  ];

  environment.global-persistence.user.directories = [
    ".local/share/bottles"
    ".local/share/protonplus" # ProtonPlus downloads
    ".config/protonplus" # ProtonPlus configs
  ];
}
