{ config, lib, pkgs, modulesPath, suites, profiles, ... }: 

{
  imports = suites.server ++
    (with profiles; [
      cloud
    ]) ++ (with profiles.users; [ tippy ]) ++
    [ nixos-hardware.nixosModules.microsoft-surface ];

  environment.graphical.enable = true;
  environment.systemPackages = with pkgs; [ 
    wezterm
    neovide
    firefox
  ];

  boot = {
    initrd = {
      availableKernelModules = [ "ata_piix" "mptspi" "uhci_hcd" "ehci_pci" "sd_mod" "sr_mod" ]; 
      kernelModules = [ "vmw_pvscsi" ];
    };
  };

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  system.stateVersion = "22.11";
}
