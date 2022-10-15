{ config, lib, pkgs, modulesPath, suites, profiles, ... }: {

  imports = suites.server ++
    suites.multimedia ++
    (with profiles; [
      cloud
    ]) ++ (with profiles.users; [ tippy ]);

  environment.systemPackages = with pkgs; [ 
    wezterm
    neovide
  ];

  boot = {
    initrd = {
      availableKernelModules = [ "ata_piix" "mptspi" "uhci_hcd" "ehci_pci" "sd_mod" "sr_mod" ]; 
      kernelModules = [ "vmw_pvscsi" ];
    };
  };

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  virtualisation.vmware.guest.enable = true;

  system.stateVersion = "22.11";
}
