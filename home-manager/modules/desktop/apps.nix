{
  pkgs,
  config,
  ...
}: {
  home.packages = with pkgs; [
    tdesktop
    thunderbird
    brasero
    k3b
    neovide
    okular
    wpsoffice
    # plasma5Packages.kdeconnect-kde
    config.nur.repos.xddxdd.baidupcs-go
    config.nur.repos.xddxdd.wechat-uos
  ];
  home.global-persistence = {
    directories = [
      ".local/share/TelegramDesktop"
      ".thunderbird"
      ".config/weixin"
      ".local/share/Kingsoft"
    ];
  };
}
