{ config, pkgs, lib, ... }:

{
  services.xserver = {
    enable = true;
    displayManager.sddm = {
      enable = true;
      settings.Wayland = {
        EnableHiDPI = true;
        SessionDir = "${pkgs.plasma5Packages.plasma-workspace}/share/wayland-sessions";
      };
    };
    displayManager.defaultSession = "plasmawayland";
    desktopManager.plasma5.enable = true;
  };

  hardware.video.hidpi.enable = true;

  environment.global-persistence.user = {
    directories = [
      ".local/share/applications"
      ".local/share/Trash"
    ];
    files = [
      ".face"
    ];
  };
}
