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
      ".local/share/anime-game-launcher"
    ];
  };
}
