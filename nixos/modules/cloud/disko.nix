{
  self,
  inputs,
  lib,
  config,
  pkgs,
  ...
}: let
  mountOptions = {mountOptions = ["discard" "noatime" "nodiratime" "ssd_spread" "compress-force=zstd" "space_cache=v2"];};
in {
  imports = [
    inputs.disko.nixosModules.disko
  ];
  disko.enableConfig = true;
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "${config.utils.disk}";
      content = {
        type = "table";
        format = "gpt";
        partitions = [
          {
            name = "bios_grub";
            start = "0";
            end = "1MiB";
            part-type = "primary";
            flags = ["bios_grub"];
          }
          {
            name = "EFI";
            start = "1MiB";
            end = "200MiB";
            fs-type = "fat32";
            bootable = true;
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          }
          {
            name = "NIXOS";
            start = "210M";
            end = "100%";
            part-type = "primary";
            content = {
              type = "btrfs";
              extraArgs = ["-f"];
              subvolumes = {
                "/nix" = mountOptions;
                "/persist" =
                  mountOptions
                  // {
                    mountpoint = "/nix/persist";
                  };
                "/rootfs" =
                  mountOptions
                  // {
                    mountpoint = "/";
                  };
              };
            };
          }
        ];
      };
    };
    # nodev = {
    #   "/" = {
    #     fsType = "tmpfs";
    #     mountOptions = [ "defaults" "mode=755" ];
    #   };
    # };
  };

  fileSystems = {
    # "/" = {
    #   fsType = "tmpfs";
    #   options = ["defaults" "mode=755"];
    # };
    "/boot" = {
      device = lib.mkForce "/dev/disk/by-partlabel/EFI";
    };

    "/" = {
      device = lib.mkForce "/dev/disk/by-partlabel/NIXOS";
    };

    "/nix" = {
      device = lib.mkForce "/dev/disk/by-partlabel/NIXOS";
    };

    "/nix/persist" = {
      device = lib.mkForce "/dev/disk/by-partlabel/NIXOS";
      neededForBoot = true;
    };
  };
  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [
      config.fileSystems."/nix".device
    ];
  };

  boot = {
    loader.grub = {
      enable = true;
      device = "${config.utils.disk}";
      efiSupport = lib.mkDefault true;
      efiInstallAsRemovable = lib.mkDefault true;
    };
    initrd.kernelModules = ["dm-snapshot" "tpm_tis" "dm_mod" "dm-crypt"];
    initrd.supportedFilesystems = ["btrfs"];
    initrd.systemd = {
      enable = true;
      services.rollback = {
        description = "Rollback BTRFS root subvolume to a pristine state";
        unitConfig.DefaultDependencies = "no";
        serviceConfig.Type = "oneshot";

        wantedBy = ["initrd.target"];
        before = ["sysroot.mount"];
        requires = ["dev-disk-by\\x2dpartlabel-NIXOS.device"];
        after = ["dev-disk-by\\x2dpartlabel-NIXOS.device"];

        script = ''
          mkdir -p /mnt
          mount -t btrfs /dev/disk/by-partlabel/NIXOS /mnt
          btrfs subvolume list -o /mnt/rootfs |
            cut -f9 -d' ' |
            while read subvolume; do
              echo "deleting /$subvolume subvolume..."
              btrfs subvolume delete "/mnt/$subvolume"
            done &&
            echo "deleting /rootfs subvolume..." &&
            btrfs subvolume delete /mnt/rootfs
          echo "restoring blank /rootfs subvolume..."
          btrfs subvolume create /mnt/rootfs
          umount /mnt
        '';
      };
    };
  };
}
