{
  pkgs,
  config,
  ...
}:
{
  home.packages = with pkgs; [
    tdesktop
    ffmpeg
    thunderbird
    neovide
    okular
    wpsoffice
    config.nur.repos.xddxdd.baidupcs-go
    # config.nur.repos.xddxdd.wechat-uos
    remmina
    element-desktop
    linux-wifi-hotspot
  ];
  dconf.settings = {
    "org/virt-manager/virt-manager/connections" = {
      autoconnect = [ "qemu+ssh://tippy@shg0:22/system" ];
      uris = [
        "qemu+ssh://tippy@shg0:22/system"
        "qemu:///system"
      ];
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
      ".config/Element"
    ];
    files = [
      ".config/monitors.xml"
    ];
  };
}
