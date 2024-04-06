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
    displayManager = {
      gdm = {
        enable = true;
        autoSuspend = false;
      };
    };
    desktopManager.gnome.enable = true;
  };

  environment.systemPackages = with pkgs; [
    weston
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
    # gnomeExtensions.allow-locked-remote-desktop
  ];
  # services.gnome.gnome-remote-desktop.enable = true;
  services.xrdp = {
    enable = true;
    openFirewall = true;
    defaultWindowManager = "${pkgs.gnome.gnome-session}/bin/gnome-session";
  };
  services.fprintd.enable = true;
  services.gnome.gnome-browser-connector.enable = true;
  services.gnome.sushi.enable = true;
  services.gvfs.enable = true;

  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };
}
