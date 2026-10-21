{ pkgs, ... }:
{
  programs.gamemode.enable = true;
  programs.gamescope = {
    enable = true;
    capSysNice = false;
  };

  # 游戏模块专用二进制缓存加速
  nix.settings = {
    substituters = [ "https://nix-gaming.cachix.org" ];
    trusted-public-keys = [ "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4=" ];
  };

  environment.systemPackages = with pkgs; [
    mangohud
    gperftools # For memory profiling if needed
  ];

  environment.global-persistence.user.directories = [
    ".config/MangoHud"
  ];
}
