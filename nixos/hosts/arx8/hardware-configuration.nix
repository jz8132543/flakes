{
  config,
  lib,
  inputs,
  ...
}:
let
  MONITOR = "eDP-1";
in
{
  imports = [
    ./edid
    ./monitors.nix
    inputs.grub2-themes.nixosModules.default
    inputs.nixos-hardware.nixosModules.common-hidpi
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    # inputs.nixos-hardware.nixosModules.common-gpu-nvidia-nonprime
  ];
  boot = {
    initrd = {
      availableKernelModules = [
        "nvme"
        "xhci_pci"
        "usbhid"
        "usb_storage"
        "sd_mod"
      ];
    };
    extraModulePackages = [ config.boot.kernelPackages.lenovo-legion-module ];
    kernelModules = [ "kvm-amd" ];
    kernelParams = [
      # "fbdev=1"
      "acpi=copy_dsdt"
      "video=${MONITOR}:2560x1600@240"
      # "nvidia_drm.modeset=1"
      # "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
      # "nvidia.NVreg_DynamicPowerManagement=2"
      # "nvidia.NVreg_OpenRmEnableUnsupportedGpus=1"
    ];
    loader = {
      efi.canTouchEfiVariables = lib.mkDefault true;
      grub = {
        device = lib.mkForce "nodev";
        efiInstallAsRemovable = lib.mkForce false;
        # useOSProber = true;
        default = 1;
        # default = "saved";
        # gfxmodeEfi = lib.mkForce "1280x800";
        extraEntries = ''
          menuentry "Windows" {
            insmod part_gpt
            insmod ntfs
            insmod search_fs_uuid
            insmod chain
            search --no-floppy --fs-uuid --set=root 628A86FC8A86CC4B
            chainloader /EFI/Microsoft/Boot/bootmgfw.efi
          }
        '';
      };
      grub2-theme = {
        enable = true;
        theme = "whitesur";
      };
    };
  };
  services = {
    # Cooling management
    thermald.enable = lib.mkDefault true;
    # AMD has better battery life with PPD over TLP:
    # https://community.frame.work/t/responded-amd-7040-sleep-states/38101/13
    power-profiles-daemon.enable = lib.mkDefault true;
    acpid.enable = true;
    zram-generator = {
      enable = true;
      settings.zram0 = {
        compression-algorithm = "zstd";
        zram-size = "ram";
      };
    };
  };
  hardware = {
    # enableAllFirmware = true;
    cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    nvidia = {
      # package = config.boot.kernelPackages.nvidiaPackages.vulkan_beta;
      modesetting.enable = true;
      nvidiaPersistenced = true;
      nvidiaSettings = true;
      # open = true;
      prime = {
        offload.enable = false;
        sync.enable = true;
        amdgpuBusId = "PCI:8:0:0";
        nvidiaBusId = "PCI:1:0:0";
      };
    };
  };
  environment.sessionVariables = {
    __GL_SYNC_DISPLAY_DEVICE = MONITOR;
    VDPAU_NVIDIA_SYNC_DISPLAY_DEVICE = MONITOR;
  };
  # home-manager.users.tippy.wayland.dpi = 144;
  utils.disk = "/dev/nvme0n1";
  nix.gc.automatic = lib.mkForce false;
}
