{ config, lib, pkgs, ...  }:

lib.mkIf config.environment.graphical.enable{
  hardware.video.hidpi.enable = true;
  sound.enable = true;
  hardware.bluetooth.enable = true;
  hardware.pulseaudio = {
    enable = true;
    support32Bit = true;
    tcp = {
      enable = true;
      anonymousClients.allowedIpRanges = [ "127.0.0.1" ];
    };
  };
  networking.networkmanager.enable = true;
  programs.light.enable = true;
  systemd.services.nix-daemon.environment = lib.mkIf config.environment.China.enable { all_proxy = "socks5://127.0.0.1:1080"; };
  environment.systemPackages = with pkgs; [
    thunderbird
    chromium
  ];
  environment.global-persistence = {
    files = [
    ];
    directories = [
     "/etc/NetworkManager"
    ];
    user.directories = [
      ".config/fcitx5"
      ".mozilla"
      ".thunderbird"
      ".local/share/TelegramDesktop"
      ".config/chromium"
    ];
  };
}
