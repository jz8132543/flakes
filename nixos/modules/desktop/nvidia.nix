{
  pkgs,
  lib,
  config,
  ...
}: {
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (pkgs.lib.getName pkg) [
      "nvidia-x11"
    ];
  services.xserver.videoDrivers = ["nvidia"];
  systemd.services.nvidia-control-devices = {
    wantedBy = [
      "multi-user.target"
    ];
  };
  # boot = {
  #   kernelParams = [ "nvidia-drm.modeset=1" ];
  #   kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
  #   # blacklistedKernelModules = ["nouveau"];
  # };
  hardware.nvidia = {
    modesetting.enable = true;
    package = config.boot.kernelPackages.nvidiaPackages.production;
    nvidiaSettings = true;
    prime = {
      offload.enable = true;
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:2:0:0";
    };
  };
  # environment.systemPackages = with pkgs; [
  #   glxinfo
  #   vulkan-tools
  #   glmark2
  #   nvidia-vaapi-driver
  # ];
}
