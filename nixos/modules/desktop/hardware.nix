{pkgs, ...}: {
  hardware = {
    opengl = {
      enable = true;
      driSupport32Bit = true;
      extraPackages = with pkgs; [intel-media-driver];
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
      xkbOptions = "caps:swapescape,caps:escape";
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
  console.font = "latarcyrheb-sun32";
  console.earlySetup = true;
  boot.supportedFilesystems = ["ntfs"];
}
