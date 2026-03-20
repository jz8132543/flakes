{ lib, ... }:
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
      # keyd owns keyboard remapping so we do not stack XKB swaps on top.
      xkb.options = lib.mkForce "";
    };
    keyd = {
      enable = true;
      keyboards.default = {
        ids = [ "*" ];
        settings.main = {
          # Tap either Shift to emit a dedicated IME toggle key on release;
          # hold it or chord it with another key to behave like normal Shift.
          leftshift = "overload(shift, macro(C-space))";
          rightshift = "overload(shift, macro(C-space))";

          # Keep Escape/CapsLock swapped for all keyboards, including hotplugged ones.
          capslock = "esc";
          esc = "capslock";
        };
      };
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
