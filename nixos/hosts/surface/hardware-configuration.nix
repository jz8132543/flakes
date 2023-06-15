{
  config,
  lib,
  inputs,
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
      grub = {
        device = lib.mkForce "nodev";
        # useOSProber = true;

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
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
