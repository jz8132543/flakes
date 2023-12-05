{lib, ...}: {
  boot = {
    initrd = {
      availableKernelModules = ["ata_piix" "mptspi" "uhci-hcd" "ehci_pci" "sd_mod" "sr_mod"];
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
  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 16384;
    }
  ];

  utils.disk = "/dev/sda";
  virtualisation.vmware.guest.enable = true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
