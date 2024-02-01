{
  pkgs,
  lib,
  nixosModules,
  ...
}: {
  imports = [nixosModules.services.acme];

  # firewall fot GSConnect
  networking.firewall.allowedTCPPorts = lib.range 1714 1764;
  networking.firewall.allowedUDPPorts = lib.range 1714 1764;

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
    gnome.polari
    gnome.gnome-session
  ];
  # services.gnome.gnome-remote-desktop.enable = true;
  # services.xrdp = {
  #   enable = true;
  #   openFirewall = true;
  #   defaultWindowManager = "${pkgs.gnome.gnome-session}/bin/gnome-session";
  # };

  services.gnome.gnome-browser-connector.enable = true;
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;
}
