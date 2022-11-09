{ config, lib, pkgs, ...  }:

lib.mkIf config.environment.graphical.enable{
  boot.supportedFilesystems = [ "ntfs" ];
  hardware = {
    video.hidpi.enable = true;
    bluetooth.enable = true;
    opengl = {
      enable = true;
      extraPackages = with pkgs; [ intel-media-driver ];
    };
  };
  console.font = "latarcyrheb-sun32";
  console.earlySetup = true;
  security.rtkit.enable = true;
  services.blueman.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };
  networking.networkmanager.enable = true;
  programs.light.enable = true;
  systemd.services.nix-daemon.environment = lib.mkIf config.environment.China.enable {
    all_proxy = "socks5://127.0.0.1:1080";
    http_proxy = "socks5://127.0.0.1:1080";
    https_proxy = "socks5://127.0.0.1:1080";
  };
  environment.systemPackages = with pkgs; [
  ];
  environment.global-persistence = {
    files = [
    ];
    directories = [
     "/etc/NetworkManager"
    ];
    user.directories = [
      ".local/state"
    ];
  };
}
