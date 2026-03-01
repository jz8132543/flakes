{
  inputs,
  lib,
  config,
  pkgs,
  ...
}:
{
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
          BIOS = {
            label = "BIOS";
            size = "1M";
            type = "EF02";
          };
          EFI = {
            label = "EFI";
            size = "200M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot/efi";
            };
          };
          NIXOS = {
            label = "NIXOS";
            end = "-0";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "/nix" = {
                  mountpoint = "/nix";
                  mountOptions = [
                    "discard"
                    "noatime"
                    "nodiratime"
                    "ssd_spread"
                    "compress=zstd"
                    "space_cache=v2"
                  ];
                };
                "/persist" = {
                  mountpoint = "/persist";
                  mountOptions = [
                    "discard"
                    "noatime"
                    "nodiratime"
                    "ssd_spread"
                    "compress=zstd"
                    "space_cache=v2"
                  ];
                };
                "/boot" = {
                  mountpoint = "/boot";
                  mountOptions = [
                    "discard"
                    "noatime"
                    "nodiratime"
                    "ssd_spread"
                    "compress=zstd"
                    "space_cache=v2"
                  ];
                };
                "/swap" = {
                  mountpoint = "/swap";
                  mountOptions = [
                    "noatime"
                    "nodiratime"
                    "nodatacow"
                  ];
                };
                "/rootfs" = {
                  mountpoint = "/";
                  mountOptions = [
                    "discard"
                    "noatime"
                    "nodiratime"
                    "ssd_spread"
                    "compress=zstd"
                    "space_cache=v2"
                  ];
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
  fileSystems."/nix".neededForBoot = true;
  fileSystems."/boot".neededForBoot = true;

  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [
      config.fileSystems."/nix".device
    ];
  };

  boot = {
    # 自动在启动时修复 GPT 错误并扩展分区
    growPartition = lib.mkDefault true;

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

        wantedBy = [ "initrd.target" ];
        before = [ "sysroot.mount" ];
        after = [ "dev-disk-by\\x2dpartlabel-NIXOS.device" ];
        requires = [ "dev-disk-by\\x2dpartlabel-NIXOS.device" ];
        path = with pkgs; [
          btrfs-progs
          coreutils
          util-linux
        ];

        script = ''
          mkdir -p /mnt
          # Use label just in case partlabel is not settles
          mount -t btrfs /dev/disk/by-partlabel/NIXOS /mnt || mount -t btrfs /dev/disk/by-label/NIXOS /mnt

          if [ -e /mnt/rootfs ]; then
            btrfs subvolume list -o /mnt/rootfs |
              cut -f9 -d' ' |
              while read subvolume; do
                echo "deleting /$subvolume subvolume..."
                btrfs subvolume delete "/mnt/$subvolume"
              done &&
              echo "deleting /rootfs subvolume..." &&
              btrfs subvolume delete /mnt/rootfs
          fi
          echo "restoring blank /rootfs subvolume..."
          btrfs subvolume create /mnt/rootfs
          umount /mnt
        '';
      };
    };
  };

  systemd.services.btrfs-resize = {
    description = "Auto-resize Btrfs filesystems to fill partition";
    wantedBy = [ "multi-user.target" ];
    after = [ "grow-partition.service" ]; # 确保从 boot.growPartition 启动的服务完成后执行
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # 动态找到所有 Btrfs 挂载点并扩容
    script = ''
      ${pkgs.btrfs-progs}/bin/btrfs filesystem resize max /nix
    '';
  };
}
