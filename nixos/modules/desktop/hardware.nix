{
  console.useXkbConfig = true;
  services = {
    xserver = {
      enable = true;
      # dpi = 144;
      # libinput.enable = true;
      # libinput.touchpad = {
      #   horizontalScrolling = true;
      #   naturalScrolling = true;
      #   tapping = true;
      #   tappingDragLock = false;
      # };
      # Swap CapsLock and Escape for all keyboards via XKB (hotplug-safe).
      xkb.options = "caps:swapescape";
    };
    # Ignore auto hibernate
    logind.settings.Login = {
      LidSwitchIgnoreInhibited = "yes";
      HandleLidSwitch = "ignore";
    };
    # pipewire = {
    #   enable = true;
    #   audio.enable = true;
    #   alsa.enable = true;
    #   alsa.support32Bit = true;
    #   pulse.enable = true;
    #   jack.enable = true;
    # };
  };
  security.rtkit.enable = true;
  boot.supportedFilesystems = [ "ntfs" ];
}
