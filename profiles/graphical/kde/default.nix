{ config, lib, ... }:

lib.mkIf
  config.services.kde.enable
{
  services.xserver = {
    enable = true;
    displayManager.sddm.enable = true;
    desktopManager.plasma5.enable = true;
  };

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
