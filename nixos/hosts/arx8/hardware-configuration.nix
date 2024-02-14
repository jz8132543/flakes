{
  config,
  lib,
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.grub2-themes.nixosModules.default
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    inputs.nixos-hardware.nixosModules.common-gpu-nvidia-nonprime
  ];
  services.acpid.enable = true;
  boot = {
    initrd = {
      availableKernelModules = ["nvme" "xhci_pci" "usbhid" "usb_storage" "sd_mod"];
      kernelModules = ["nvidia"];
    };
    extraModulePackages = [config.boot.kernelPackages.lenovo-legion-module];
    kernelModules = ["kvm-amd" "nvidia_uvm"];
    kernelParams = [
      "nvidia_drm.modeset=1"
      "fbdev=1"
      "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
      "nvidia.NVreg_DynamicPowerManagement=2"
      "nvidia.NVreg_OpenRmEnableUnsupportedGpus=1"
    ];
    loader = {
      efi.canTouchEfiVariables = lib.mkDefault true;
      grub = {
        device = lib.mkForce "nodev";
        efiInstallAsRemovable = lib.mkForce false;
        # useOSProber = true;
        default = 0;
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
  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 8192;
    }
  ];
  utils.disk = "/dev/nvme0n1";
  # Cooling management
  services.thermald.enable = lib.mkDefault true;
  # AMD has better battery life with PPD over TLP:
  # https://community.frame.work/t/responded-amd-7040-sleep-states/38101/13
  services.power-profiles-daemon.enable = lib.mkDefault true;
  hardware = {
    cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    # amdgpu.loadInInitrd = false;
    nvidia = {
      package = config.boot.kernelPackages.nvidiaPackages.vulkan_beta;
      # package = config.boot.kernelPackages.nvidiaPackages.production;
      modesetting.enable = true;
      nvidiaSettings = true;
      prime = {
        sync.enable = true;
        amdgpuBusId = "PCI:8:0:0";
        nvidiaBusId = "PCI:1:0:0";
      };
    };
  };
  home-manager.users.tippy.wayland.dpi = 144;
  services.zram-generator = {
    enable = true;
    settings.zram0 = {
      compression-algorithm = "zstd";
      zram-size = "ram";
    };
  };
}
