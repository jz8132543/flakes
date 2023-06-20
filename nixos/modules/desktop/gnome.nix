{
  config,
  pkgs,
  lib,
  ...
}: {
  services.xserver = {
    enable = true;
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
  };

  # prevent gdm auto suspend before login
  services.xserver.displayManager.gdm.autoSuspend = false;

  environment.systemPackages = with pkgs; [
    kooha
    pulseaudio
    wl-clipboard
    gnome.gnome-boxes
    gnome.devhelp
    gnome.dconf-editor
    gnome.gnome-sound-recorder
    gnome.gnome-power-manager
    gnome.gnome-tweaks
    gnome.gnome-remote-desktop
    gnome.polari
  ];

  services.gnome.gnome-browser-connector.enable = true;
}
