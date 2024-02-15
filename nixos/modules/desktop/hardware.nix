{inputs, ...}: {
  imports = [inputs.xremap-flake.nixosModules.default];
  hardware = {
    opengl = {
      enable = true;
      driSupport = true;
      driSupport32Bit = true;
    };
  };
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
      # xkb.options = "caps:swapescape,caps:escape";
    };
    xremap.config.modmap = [
      {
        name = "Global";
        remap = {"CapsLock" = "Esc";}; # globally remap CapsLock to Esc
      }
      {
        name = "Global";
        remap = {"ESC" = "CapsLock";}; # globally remap CapsLock to Esc
      }
    ];
    # Ignore auto hibernate
    logind.extraConfig = ''
      LidSwitchIgnoreInhibited=yes
      HandleLidSwitch=ignore
    '';
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
  console.font = "latarcyrheb-sun32";
  console.earlySetup = true;
  boot.supportedFilesystems = ["ntfs"];
}
