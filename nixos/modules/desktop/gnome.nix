{
  pkgs,
  lib,
  nixosModules,
  ...
}:
{
  imports = [ nixosModules.services.acme ];

  programs.kdeconnect = {
    enable = true;
    package = pkgs.gnomeExtensions.gsconnect;
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        DiscoverableTimeout = "0";
        Experimental = true;
      };
    };
  };

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
    # services.gnome.gnome-remote-desktop.enable = true;
    xrdp = {
      enable = true;
      openFirewall = true;
      defaultWindowManager = "${pkgs.gnome-session}/bin/gnome-session";
    };
    fprintd.enable = true;
    gnome = {
      gnome-browser-connector.enable = true;
      sushi.enable = true;
    };
    gvfs.enable = true;
    logind.settings.Login = {
      # Short-press power key only turns off the screen (handled via GNOME
      # custom keybinding below). Long-press keeps system poweroff as a
      # safety fallback when the system is unresponsive.
      HandlePowerKey = "ignore";
      HandlePowerKeyLongPress = "poweroff";
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

  # Let Home Manager own user-level GNOME dconf keys. Keeping locks here makes
  # `home-manager-tippy.service` fail when it tries to write the same keys.
  programs.dconf.enable = true;

  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };
}
