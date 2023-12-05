{lib, ...}: {
  boot = {
    initrd = {
      availableKernelModules = ["ata_piix" "mpdspi" "uhci-hcd" "ehci_pci" "sd_mod" "sr_mod"];
    };
    kernelModules = ["kvm-amd"];
    loader = {
      efi.canTouchEfiVariables = lib.mkDefault true;
      grub = {
        device = lib.mkForce "nodev";
        efiInstallAsRemovable = lib.mkForce false;
      };
    };
  };
  virtualisation.vmware.guest.enable = true;
}
