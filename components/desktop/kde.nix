{ pkgs, ... }:
{
  services.xserver.desktopManager.plasma5 = {
    enable = true;
    useQtScaling = true;
    excludePackages = with pkgs; [
      oxygen
      elisa
      khelpcenter
      okular
    ];
  };

  services.xserver.displayManager = {
    autoLogin.enable = true;
    autoLogin.user = "tippy";
    sddm.enable = true;
  };

  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;

  xdg.portal.enable = true;
}
