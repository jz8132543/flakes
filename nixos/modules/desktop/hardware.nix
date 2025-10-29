{ inputs, ... }:
{
  imports = [ inputs.xremap-flake.nixosModules.default ];
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
    xremap = {
      enable = true;
      config.modmap = [
      {
        name = "Global";
        remap = {
          "CapsLock" = "Esc";
        }; # globally remap CapsLock to Esc
      }
      {
        name = "Global";
        remap = {
          "ESC" = "CapsLock";
        }; # globally remap CapsLock to Esc
      }
    ];};
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
  boot.supportedFilesystems = [ "ntfs" ];
}
