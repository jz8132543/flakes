{ pkgs, ... }:
{
  programs.gamemode.enable = true;
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };
  environment.systemPackages = [
    pkgs.steam-run
    (pkgs.makeDesktopItem {
      name = "steam-hidpi";
      desktopName = "Steam (HiDPI)";
      exec = "env GDK_SCALE=\"1.5\" steam %U";
      categories = [
        "Game"
      ];
      icon = "steam";
    })
  ];
  environment.global-persistence.user = {
    directories = [
      ".steam"
      ".local/share/Steam"
    ];
  };
}
