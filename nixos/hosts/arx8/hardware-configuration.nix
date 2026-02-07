{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:
let
  MONITOR = "eDP-1";
in
{
  imports = [
    ./edid
    # ./monitors.nix
    inputs.grub2-themes.nixosModules.default
    inputs.nixos-hardware.nixosModules.common-hidpi
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    # inputs.nixos-hardware.nixosModules.common-gpu-nvidia-nonprime
  ];
  boot = {
    initrd = {
      availableKernelModules = [
        "nvme"
        "xhci_pci"
        "usbhid"
        "usb_storage"
        "sd_mod"
      ];
    };
    extraModulePackages = [ config.boot.kernelPackages.lenovo-legion-module ];
    kernelModules = [
      "kvm-amd"
      "lenovo-legion-module"
    ];
    kernelParams = [
      # "fbdev=1"
      "acpi=copy_dsdt"
      "video=${MONITOR}:2560x1600@240"
      # "nvidia_drm.modeset=1"
      # "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
      # "nvidia.NVreg_DynamicPowerManagement=2"
      # "nvidia.NVreg_OpenRmEnableUnsupportedGpus=1"
    ];
    loader = {
      efi.canTouchEfiVariables = lib.mkDefault true;
      grub = {
        device = lib.mkForce "nodev";
        efiInstallAsRemovable = lib.mkForce false;
        # useOSProber = true;
        default = 0;
        # default = "saved";
        # gfxmodeEfi = lib.mkForce "1280x800";
        extraEntries = ''
          menuentry "Windows" {
            insmod part_gpt
            insmod ntfs
            insmod fat
            insmod search_fs_uuid
            insmod chain
            search --no-floppy --set=root --file /EFI/Microsoft/Boot/bootmgfw.efi
            chainloader /EFI/Microsoft/Boot/bootmgfw.efi
          }
        '';
      };
      grub2-theme = {
        enable = true;
        theme = "vimix";
        footer = true;
        # customResolution = "1920x1200";
      };
    };
  };
  services = {
    # Cooling management
    thermald.enable = lib.mkDefault true;
    # AMD has better battery life with PPD over TLP:
    # https://community.frame.work/t/responded-amd-7040-sleep-states/38101/13
    power-profiles-daemon.enable = lib.mkDefault true;
    acpid.enable = true;
    zram-generator = {
      enable = true;
      settings.zram0 = {
        compression-algorithm = "zstd";
        zram-size = "ram";
      };
    };
  };
  hardware = {
    # enableAllFirmware = true;
    cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    # nvidia = {
    #   # package = config.boot.kernelPackages.nvidiaPackages.vulkan_beta;
    #   modesetting.enable = true;
    #   nvidiaPersistenced = true;
    #   nvidiaSettings = true;
    #   open = false;
    #   prime = {
    #     offload.enable = false;
    #     sync.enable = true;
    #     amdgpuBusId = "PCI:8:0:0";
    #     nvidiaBusId = "PCI:1:0:0";
    #   };
    # };
    nvidia = {
      modesetting.enable = true;
      powerManagement.enable = true; # 开启显卡电源管理，解决风扇不转或耗电快
      powerManagement.finegrained = true; # 针对 40 系显卡的精细电源控制
      open = lib.mkForce true; # 2023 款显卡支持 NVIDIA 官方开源内核模块，更符合 NixOS 哲学
      package = config.boot.kernelPackages.nvidiaPackages.stable;

      prime = {
        offload.enable = true;
        offload.enableOffloadCmd = true;
        # 这里的 Bus ID 需要通过 lspci 命令确认后修改
        amdgpuBusId = "PCI:8:0:0";
        nvidiaBusId = "PCI:1:0:0";
      };
    };
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        libva-vdpau-driver
        libvdpau-va-gl
        nvidia-vaapi-driver
      ];
    };
  };
  environment.sessionVariables = {
    __GL_SYNC_DISPLAY_DEVICE = MONITOR;
    VDPAU_NVIDIA_SYNC_DISPLAY_DEVICE = MONITOR;
  };
  home-manager.users.tippy.wayland.dpi = 144;
  utils.disk = "/dev/nvme0n1";
  nix.gc.automatic = lib.mkForce false;
  environment.systemPackages = with pkgs; [
    lenovo-legion
    nvtopPackages.full # 监控显卡状态
    libva-utils
  ];
}
