{ config, lib, pkgs, modulesPath, suites, profiles, ... }: 

{
  imports = suites.server ++
    (with profiles; [
      cloud
    ]) ++ (with profiles.users; [ tippy ]);

  environment.graphical.enable = true;
  environment.systemPackages = with pkgs; [ 
    wezterm
    neovide
    firefox
  ];

  boot = {
    initrd = {
      availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" ]; 
    };
    kernelModules = [ "kvm-intel" "vfio" "vfio_iommu_type1" "vfio_pci" "vfio_virqfd" ];
    kernelParams = [ "intel_iommu=on" "iommu=pt" "mitigations=off" "nowatchdog" ];
    extraModprobeConfig = ''
      options i915 enable_guc=2
      options i915 enable_fbc=1
      options kvm_intel nested=1
    '';
  };

  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  nix.settings.substituters = [ "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store" ];

  system.stateVersion = "22.11";
}

