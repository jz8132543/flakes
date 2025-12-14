{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    inputs.nixos-hardware.nixosModules.common-hidpi
    inputs.nixos-hardware.nixosModules.common-gpu-nvidia-nonprime
  ];

  hardware = {
    graphics = {
      enable = true;
      # driSupport = true;
      # driSupport32Bit = true;
      extraPackages = with pkgs; [
        libvdpau-va-gl
        nvidia-vaapi-driver
        libva-vdpau-driver
      ];
    };
    nvidia.package = config.boot.kernelPackages.nvidiaPackages.beta;
  };
  boot = {
    kernelModules = [
      "nvidia"
      "nvidia_uvm"
      "nvidia_modeset"
      "nvidia_drm"
    ];
    kernelParams = [
      "nvidia_drm.modeset=1"
      "nvidia-drm.fbdev=1"
      "nvidia-modeset.hdmi_deepcolor=1"
      "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
      "nvidia.NVreg_OpenRmEnableUnsupportedGpus=1"
      # "nvidia.NVreg_DynamicPowerManagement=2"
    ];
  };
  services.xserver.videoDrivers = lib.mkDefault [ "nvidia" ];
  environment.sessionVariables = {
    __GL_GSYNC_ALLOWED = "1";
    # __GL_SYNC_DISPLAY_DEVICE = "HDMI-A-1";
    __GL_SYNC_TO_VBLANK = "1";
    __GL_VRR_ALLOWED = "1";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
    LIBVA_DRIVER_NAME = "nvidia";
    SDL_VIDEODRIVER = "wayland";
    # VDPAU_NVIDIA_SYNC_DISPLAY_DEVICE = "HDMI-A-1";
  };
}
