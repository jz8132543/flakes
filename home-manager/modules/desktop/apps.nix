{
  pkgs,
  config,
  ...
}: {
  home.packages = with pkgs; [
    tdesktop
    thunderbird
    neovide
    okular
    config.nur.repos.xddxdd.baidupcs-go
  ];
  home.global-persistence = {
    directories = [
      ".local/share/TelegramDesktop"
      ".thunderbird"
    ];
  };
}
