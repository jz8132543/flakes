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
    # plasma5Packages.kdeconnect-kde
    config.nur.repos.xddxdd.baidupcs-go
    config.nur.repos.xddxdd.wechat-uos
  ];
  home.global-persistence = {
    directories = [
      ".local/share/TelegramDesktop"
      ".thunderbird"
      ".config/weixin"
    ];
  };
}
