{
  config,
  lib,
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.grub2-themes.nixosModules.default
  ];
  boot = {
    initrd = {
      availableKernelModules = ["xhci_pci" "nvme" "usb_storage" "sd_mod"];
    };
    kernelModules = ["kvm-intel" "vfio" "vfio_iommu_type1" "vfio_pci" "vfio_virqfd"];
    kernelParams = ["intel_iommu=on" "iommu=pt" "mitigations=off" "nowatchdog"];
    extraModprobeConfig = ''
      options i915 enable_guc=2
      options i915 enable_fbc=1
      options kvm_intel nested=1
      options kvm_intel emulate_invalid_guest_state=0
      options kvm ignore_msrs=1
    '';
    loader = {
      efi.canTouchEfiVariables = lib.mkDefault true;
      grub = {
        # theme = pkgs.nixos-grub2-theme;
        device = lib.mkForce "nodev";
        efiInstallAsRemovable = lib.mkForce false;
        # useOSProber = true;

        default = 0;
        gfxmodeEfi = lib.mkForce "1600x1200";
        extraEntries = ''
          menuentry "Windows" {
            insmod part_gpt
            insmod ntfs
            insmod search_fs_uuid
            insmod chain
            search --no-floppy --fs-uuid --set=root E4CAC872CAC84312
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
  services.xserver.videoDrivers = ["nvidia"];
  systemd.services.nvidia-control-devices = {
    wantedBy = [
      "multi-user.target"
    ];
  };
  hardware.nvidia = {
    modesetting.enable = true;
    # package = config.boot.kernelPackages.nvidiaPackages.production;
    nvidiaSettings = true;
    nvidiaPersistenced = true;
    prime = {
      offload.enable = true;
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:2:0:0";
    };
    powerManagement = {
      enable = true;
      finegrained = true;
    };
  };
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
