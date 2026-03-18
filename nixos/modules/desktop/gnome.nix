{
  pkgs,
  lib,
  nixosModules,
  ...
}:
{
  imports = [ nixosModules.services.acme ];

  # firewall fot GSConnect
  networking.firewall.allowedTCPPorts = lib.range 1714 1764;
  networking.firewall.allowedUDPPorts = lib.range 1714 1764;

  services = {
    xserver.enable = true;
    displayManager = {
      gdm = {
        enable = true;
        autoSuspend = false;
      };
      sddm.enable = lib.mkForce false;
    };
    desktopManager = {
      gnome.enable = true;
      plasma6.enable = lib.mkForce false;
    };
  };

  environment.systemPackages = with pkgs; [
    weston
    kooha
    pulseaudio
    wl-clipboard
    gnome-power-manager
    gnome-tweaks
    polari
    # TEST
    gnome-session
    gnome-boxes
    devhelp
    dconf-editor
    gnome-sound-recorder
    gnomeExtensions.dash-to-dock
    # gnomeExtensions.allow-locked-remote-desktop
  ];
  # services.gnome.gnome-remote-desktop.enable = true;
  services.xrdp = {
    enable = true;
    openFirewall = true;
    defaultWindowManager = "${pkgs.gnome-session}/bin/gnome-session";
  };
  services.fprintd.enable = true;
  services.gnome.gnome-browser-connector.enable = true;
  services.gnome.sushi.enable = true;
  services.gvfs.enable = true;

  # System-wide dconf defaults for GNOME dash-to-dock (ensure autohide)
  environment.etc."dconf/profile/user".text = ''
    user-db:user
    system-db:local
  '';

  environment.etc."dconf/db/local.d/00-dock".text = ''
    [org/gnome/shell/extensions/dash-to-dock]
    autohide=true
    dock-fixed=false
    intellihide-mode='ALL_WINDOWS'
    apply-custom-theme=true
    custom-theme-shrink=true
  '';

  # Optional: lock the autohide key so users cannot override it
  environment.etc."dconf/db/local.d/locks/dash-to-dock".text = ''
    /org/gnome/shell/extensions/dash-to-dock/autohide
  '';

  # Ensure the dconf database is rebuilt on system activation
  system.activationScripts.dconf-update = {
    text = ''
      ${pkgs.dconf}/bin/dconf update || true
    '';
    deps = [ "users" ];
  };

  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };
}
