{
  inputs,
  lib,
  config,
  ...
}: let
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
        type = "gpt";
        partitions = {
          bios = {
            size = "1M";
            type = "EF02";
          };
          EFI = {
            label = "EFI";
            start = "1MiB";
            end = "200MiB";
            type = "ef02";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot/efi";
            };
          };
          NIXOS = {
            label = "NIXOS";
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = ["-f"];
              subvolumes = {
                "/nix" = {
                  mountpoint = "/nix";
                  mountOptions = ["discard" "noatime" "nodiratime" "ssd_spread" "compress-force=zstd" "space_cache=v2"];
                };
                "/persist" = {
                  mountpoint = "/persist";
                  mountOptions = ["discard" "noatime" "nodiratime" "ssd_spread" "compress-force=zstd" "space_cache=v2"];
                };
                "/boot" = {
                  mountpoint = "/boot";
                  mountOptions = ["discard" "noatime" "nodiratime" "ssd_spread" "compress-force=zstd" "space_cache=v2"];
                };
                "/swap" = {
                  mountpoint = "/swap";
                  mountOptions = ["discard" "noatime" "nodiratime" "ssd_spread" "compress-force=zstd" "space_cache=v2"];
                };
                "/rootfs" = {
                  mountpoint = "/";
                  mountOptions = ["discard" "noatime" "nodiratime" "ssd_spread" "compress-force=zstd" "space_cache=v2"];
                };
              };
            };
          };
        };
      };
    };
    # nodev = {
    #   "/" = {
    #     fsType = "tmpfs";
    #     mountOptions = [ "defaults" "mode=755" ];
    #   };
    # };
  };

  fileSystems."/persist".neededForBoot = true;

  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [
      config.fileSystems."/nix".device
    ];
  };

  boot = {
    loader = {
      timeout = 2;
      efi.efiSysMountPoint = "/boot/efi";
      grub = {
        enable = true;
        device = "${config.utils.disk}";
        efiSupport = lib.mkDefault true;
        efiInstallAsRemovable = lib.mkDefault true;
      };
    };
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
