{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    inputs.grub2-themes.nixosModules.default
  ];
  boot = {
    extraModulePackages = [
      # config.boot.kernelPackages.v4l2loopback
    ];
    initrd = {
      availableKernelModules = [
        "xhci_pci"
        "nvme"
        "usb_storage"
        "sd_mod"
      ];
    };
    kernelModules = [
      "kvm-intel"
      "ucsi_acpi"
      # "v4l2loopback"
      # "vfio"
      # "vfio_iommu_type1"
      # "vfio_pci"
      # "vfio_virqfd"
    ];
    kernelParams = [
      "intel_iommu=on"
      "iommu=pt"
      "mitigations=off"
      "nowatchdog"
    ];
    extraModprobeConfig = ''
      # 禁用 FBC 和 PSR，解决 GNOME Wayland 桌面滑动掉帧卡顿
      options i915 enable_fbc=0 enable_psr=0
      options kvm_intel nested=1
      options kvm_intel emulate_invalid_guest_state=0
      options kvm ignore_msrs=1
      options uvcvideo quirks=0x80
    '';
    loader = {
      efi.canTouchEfiVariables = lib.mkDefault true;
      grub = {
        # theme = pkgs.nixos-grub2-theme;
        device = lib.mkForce "nodev";
        efiInstallAsRemovable = lib.mkForce false;
        # useOSProber = true;

        default = 0;
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
  hardware.nvidia = {
    #
    #   modesetting.enable = true;
    package = lib.mkForce config.boot.kernelPackages.nvidiaPackages.legacy_580;
    prime = {
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:2:0:0";
    };
    #   nvidiaSettings = true;
    #   nvidiaPersistenced = true;
    #   prime = {
    #     sync.enable = true;
    #     # offload.enable = true;
    #     intelBusId = "PCI:0:2:0";
    #     nvidiaBusId = "PCI:2:0:0";
    #   };
    #   powerManagement = {
    #     enable = true;
    #     finegrained = false;
    #   };
  };
  # 1. 禁用 UPower 和 GNOME 的默认低电量关机动作
  services.upower.criticalPowerAction = "Ignore";
  services.upower.allowRiskyCriticalPowerAction = true;
  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/settings-daemon/plugins/power".critical-battery-action = "nothing";
    }
  ];

  # 2. Udev 仅保留事件触发
  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", ACTION=="change", RUN+="${pkgs.systemd}/bin/systemctl --no-block start battery-guard.service"
  '';

  # 3. 极简守护服务
  systemd.services.battery-guard = {
    path = with pkgs; [
      coreutils
      gnugrep
      systemd
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      grep -q 1 /sys/class/power_supply/*/online 2>/dev/null && exit 0
      BAT=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | sort -n | head -n 1)
      [ "''${BAT:-100}" -le 5 ] && systemctl poweroff
    '';
  };
  utils.disk = "/dev/nvme0n1";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
