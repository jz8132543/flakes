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
      availableKernelModules = [ "nvme" "xhci_pci" "usbhid" "usb_storage" "sd_mod" ];
    };
    kernelModules = ["kvm-amd"];
    kernelParams = ["acpi=off"];
    loader = {
      efi.canTouchEfiVariables = lib.mkDefault true;
      grub = {
        # theme = pkgs.nixos-grub2-theme;
        device = lib.mkForce "nodev";
        efiInstallAsRemovable = lib.mkForce false;
        # useOSProber = true;

        default = 1;
        gfxmodeEfi = lib.mkForce "1600x1200";
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
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  utils.disk = "/dev/nvme0n1";
  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 8192;
    }
  ];
}
