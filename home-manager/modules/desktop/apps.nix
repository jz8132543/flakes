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
  home.persistence."/nix/persist/home/tippy" = {
    directories = [
      ".local/share/TelegramDesktop"
      ".thunderbird"
      ".config/clash-verge"
      ".local/share/anime-game-launcher"
    ];
  };
}
