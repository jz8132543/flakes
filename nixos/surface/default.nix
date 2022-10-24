{ self, inputs, config, lib, pkgs, ... }:

{
  imports = [
    ../common.nix
  ];

  environment.systemPackages = with pkgs; [
    wezterm
    neovide
    firefox
  ];

  boot = {
    initrd = {
      availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" ]; 
    };
    kernelModules = [ "kvm-intel" ];
  };

  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  nix.settings.substituters = [ "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store" ];

  system.stateVersion = "22.11";
}

