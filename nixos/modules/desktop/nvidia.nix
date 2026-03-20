{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.desktop.nvidia;
in
{
  imports = [
    inputs.nixos-hardware.nixosModules.common-hidpi
    inputs.nixos-hardware.nixosModules.common-gpu-nvidia-nonprime
  ];

  options.desktop.nvidia = {
    mode = lib.mkOption {
      type = lib.types.enum [
        "offload"
        "sync"
      ];
      default = "offload";
      description = ''
        NVIDIA PRIME mode.
        `offload` keeps the integrated GPU as default and uses the NVIDIA GPU on demand.
        `sync` renders the full desktop on the NVIDIA GPU.
      '';
    };
  };

  config = lib.mkMerge [
    {
      hardware = {
        graphics = {
          enable = true;
          enable32Bit = true;
          extraPackages = with pkgs; [
            libvdpau-va-gl
            nvidia-vaapi-driver
            libva-vdpau-driver
          ];
        };
        nvidia = {
          package = config.boot.kernelPackages.nvidiaPackages.stable;
          open = lib.mkDefault false;
          modesetting.enable = true;
          nvidiaSettings = true;
          powerManagement.enable = true;
        };
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
        ];
      };

      services.xserver.videoDrivers = lib.mkDefault [ "nvidia" ];

      environment.sessionVariables = {
        __GL_GSYNC_ALLOWED = "1";
        __GL_SYNC_TO_VBLANK = "1";
        __GL_VRR_ALLOWED = "1";
        SDL_VIDEODRIVER = "wayland";
      };

    }

    (lib.mkIf (cfg.mode == "offload") {
      environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

      hardware.nvidia = {
        powerManagement.finegrained = lib.mkDefault true;
        prime = {
          offload.enable = true;
          offload.enableOffloadCmd = lib.mkDefault true;
          sync.enable = false;
        };
      };
    })

    (lib.mkIf (cfg.mode == "sync") {
      environment.sessionVariables = {
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        GBM_BACKEND = "nvidia-drm";
        LIBVA_DRIVER_NAME = "nvidia";
      };

      hardware.nvidia = {
        powerManagement.finegrained = lib.mkDefault false;
        prime = {
          offload.enable = false;
          sync.enable = true;
        };
      };
    })
  ];
}
