{ pkgs, ... }:
{
  programs.gamemode.enable = true;
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    extraCompatPackages = with pkgs; [ proton-ge-bin ];
  };
  environment.systemPackages = [
    pkgs.steam-run
  ];
  environment.global-persistence.user = {
    directories = [
      ".steam"
      ".local/share/Steam"
    ];
  };
}
