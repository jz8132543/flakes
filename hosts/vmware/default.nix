{ config, lib, pkgs, modulesPath, suites, profiles, ... }: {

  imports = suites.server ++
    suites.multimedia ++
    (with profiles; [
      cloud
    ]) ++ (with profiles.users; [ tippy ]);

  environment.systemPackages = with pkgs; [ ];

  services.kde.enable = true;

  boot = {
    initrd = {
      availableKernelModules = [ "ata_piix" "mptspi" "uhci_hcd" "ehci_pci" "sd_mod" "sr_mod" ]; 
      kernelModules = [ "vmw_pvscsi" ];
    };
  };

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  system.stateVersion = "22.11";
}
