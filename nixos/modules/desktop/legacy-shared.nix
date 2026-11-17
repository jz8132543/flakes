{
  config,
  lib,
  pkgs,
  ...
}:
{
  # The archived GNOME module still supplies these when it is enabled.
  config = lib.mkIf (!config.desktop.gnome.enable) {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings.General = {
        DiscoverableTimeout = "0";
        Experimental = true;
      };
    };

    services = {
      fprintd.enable = true;
      gnome = {
        gnome-keyring.enable = true;
        sushi.enable = true;
      };
      gvfs.enable = true;
      logind.settings.Login = {
        # The compositor handles short presses; retain the long-press fallback.
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
      polari
      gnome-boxes
      devhelp
      dconf-editor
      gnome-sound-recorder
      nautilus
      nautilus-python
    ];

    programs.dconf.enable = true;
    systemd.targets = {
      sleep.enable = false;
      suspend.enable = false;
      hibernate.enable = false;
      hybrid-sleep.enable = false;
    };
  };
}
