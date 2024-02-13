{
  config,
  lib,
  inputs,
  pkgs,
  ...
}: let
  nvidia_x11 = config.hardware.nvidia.package;
  cfg = config.lun.nvidia-gpu-standalone;
  module = nvidia_x11.bin;
in {
  imports = [
    inputs.grub2-themes.nixosModules.default
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    inputs.nixos-hardware.nixosModules.common-gpu-nvidia-nonprime
    # inputs.nixos-hardware.nixosModules.common-gpu-amd
  ];
  boot.extraModulePackages = [module config.boot.kernelPackages.lenovo-legion-module];
  hardware.firmware = [nvidia_x11.firmware];
  hardware.opengl.extraPackages = [nvidia_x11.out];
  hardware.opengl.extraPackages32 = [nvidia_x11.lib32];
  services.acpid.enable = true;
  services.udev.extraRules = ''
    KERNEL=="nvidia", RUN+="${pkgs.runtimeShell} -c 'mknod -m 666 /dev/nvidiactl c $$(grep nvidia-frontend /proc/devices | cut -d \  -f 1) 255'"
    KERNEL=="nvidia", RUN+="${pkgs.runtimeShell} -c 'for i in $$(cat /proc/driver/nvidia/gpus/*/information | grep Minor | cut -d \  -f 4); do mknod -m 666 /dev/nvidia$${i} c $$(grep nvidia-frontend /proc/devices | cut -d \  -f 1) $${i}; done'"
    KERNEL=="nvidia_modeset", RUN+="${pkgs.runtimeShell} -c 'mknod -m 666 /dev/nvidia-modeset c $$(grep nvidia-frontend /proc/devices | cut -d \  -f 1) 254'"
    KERNEL=="nvidia_uvm", RUN+="${pkgs.runtimeShell} -c 'mknod -m 666 /dev/nvidia-uvm c $$(grep nvidia-uvm /proc/devices | cut -d \  -f 1) 0'"
    KERNEL=="nvidia_uvm", RUN+="${pkgs.runtimeShell} -c 'mknod -m 666 /dev/nvidia-uvm-tools c $$(grep nvidia-uvm /proc/devices | cut -d \  -f 1) 1'"
  '';
  boot = {
    initrd = {
      availableKernelModules = ["nvme" "xhci_pci" "usbhid" "usb_storage" "sd_mod"];
      kernelModules = ["kvm-amd" "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm"];
      # kernelModules = ["nvidia"];
    };
    # extraModulePackages = [config.boot.kernelPackages.lenovo-legion-module config.boot.kernelPackages.nvidia_x11];
    kernelModules = ["kvm-amd" "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm"];
    kernelParams = [
      "nvidia_drm.modeset=1"
      # "fbdev=1"
      "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
      "nvidia.NVreg_DynamicPowerManagement=2"
      "nvidia.NVreg_OpenRmEnableUnsupportedGpus=1"
      "amd_iommu=pgtbl_v2"
      "iommu=pt"
      "acpi=copy_dsdt"
      "tsc=reliable"
      "clocksource=tsc"
      "acpi.prefer_microsoft_guid=1"
      "s2idle.prefer_microsoft_guid=1"
    ];
    loader = {
      efi.canTouchEfiVariables = lib.mkDefault true;
      grub = {
        # theme = pkgs.nixos-grub2-theme;
        device = lib.mkForce "nodev";
        efiInstallAsRemovable = lib.mkForce false;
        # useOSProber = true;
        default = 0;
        gfxmodeEfi = lib.mkForce "1280x800";
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
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  utils.disk = "/dev/nvme0n1";
  # Cooling management
  services.thermald.enable = lib.mkDefault true;
  hardware = {
    # amdgpu.loadInInitrd = false;
    nvidia = {
      modesetting.enable = true;
      # powerManagement.enable = true;
      nvidiaSettings = true;
      # prime = {
      #   amdgpuBusId = "PCI:8:0:0";
      #   nvidiaBusId = "PCI:1:0:0";
      # };
    };
  };
  services.autorandr = {
    enable = true;
    profiles = {
      default = {
        fingerprint.eDP-1 = "eDP-2 --CONNECTED-BUT-EDID-UNAVAILABLE--eDP-2";
        config = {
          eDP-1 = {
            enable = true;
            primary = true;
            position = "0x0";
            mode = "2560x1600";
            #gamma = "1.0:0.909:0.833";
            rate = "60.00";
            scale = {
              x = 0.5;
              y = 0.5;
            };
          };
        };
      };
    };
  };
}
