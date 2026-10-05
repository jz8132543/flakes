{ pkgs, ... }:
{
  programs.gamemode.enable = true;
  programs.gamescope = {
    enable = true;
    capSysNice = false;
  };

  environment.systemPackages = with pkgs; [
    mangohud
    gperftools # For memory profiling if needed
  ];

  environment.global-persistence.user.directories = [
    ".config/MangoHud"
  ];
}
