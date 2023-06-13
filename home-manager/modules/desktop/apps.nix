{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    tdesktop
    thunderbird
    neovide
  ];
  home.global-persistence = {
    directories = [
      ".local/share/TelegramDesktop"
      ".thunderbird"
      ".config/clash-verge"
      ".local/share/anime-game-launcher"
      ".steam"
      ".local/share/Steam"
    ];
  };
}
