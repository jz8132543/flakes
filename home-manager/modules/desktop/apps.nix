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
    wpsoffice
    # plasma5Packages.kdeconnect-kde
    config.nur.repos.xddxdd.baidupcs-go
    # config.nur.repos.xddxdd.wechat-uos
    remmina
    element-desktop
  ];
  dconf.settings = {
    "org/virt-manager/virt-manager/connections" = {
      autoconnect = ["qemu+ssh://tippy@shg0:22/system"];
      uris = ["qemu+ssh://tippy@shg0:22/system" "qemu:///system"];
    };
    "org/virt-manager/virt-manager/vmlist-fields" = {
      disk-usage = true;
      network-traffic = true;
    };
  };
  home.global-persistence = {
    directories = [
      ".local/share/TelegramDesktop"
      ".thunderbird"
      ".config/weixin"
      ".local/share/Kingsoft"
    ];
  };
}
