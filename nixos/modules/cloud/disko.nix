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
      imageSize = "6G";
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
              subvolumes =
                let
                  btrfsOptions =
                    if config.environment.minimal or false then
                      [
                        "noatime"
                        "compress=zstd:1"
                        "space_cache=v2"
                        "commit=30"
                        "ssd_spread"
                        "flushoncommit"
                      ]
                    else
                      [
                        "noatime"
                        "compress-force=zstd"
                        "space_cache=v2"
                        "commit=30"
                        "ssd_spread"
                        "flushoncommit"
                      ];
                in
                {
                  "/nix" = {
                    mountpoint = "/nix";
                    mountOptions = btrfsOptions;
                  };
                  "/persist" = {
                    mountpoint = "/persist";
                    mountOptions = btrfsOptions;
                  };
                  "/boot" = {
                    mountpoint = "/boot";
                    mountOptions = btrfsOptions;
                  };
                  "/swap" = {
                    mountpoint = "/swap";
                    mountOptions = [
                      "noatime"
                      "nodatacow"
                      "commit=${if config.environment.minimal or false then "120" else "60"}"
                    ];
                  };
                  "/rootfs" = {
                    mountpoint = "/";
                    mountOptions = btrfsOptions;
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
          systemd
          util-linux
        ];

        script = ''
          set -eu

          # 等待 udev 完成设备节点与 by-label/by-partlabel 符号链接创建
          udevadm settle || true

          mkdir -p /mnt /mnt/rootfs

          disk=""
          if [ -e /dev/disk/by-partlabel/NIXOS ]; then
            disk="/dev/disk/by-partlabel/NIXOS"
          elif [ -e /dev/disk/by-label/NIXOS ]; then
            disk="/dev/disk/by-label/NIXOS"
          else
            echo "rollback: cannot find NIXOS btrfs device" >&2
            exit 1
          fi

          # 默认只挂载 rootfs 子卷到 /mnt/rootfs
          if mount -o subvol=rootfs "$disk" /mnt/rootfs; then
            mounted_rootfs=1
          else
            mounted_rootfs=0
          fi

          cleanup() {
            mountpoint -q /mnt/rootfs && umount /mnt/rootfs || true
            mountpoint -q /mnt && umount /mnt || true
          }
          trap cleanup EXIT

          if [ "$mounted_rootfs" -eq 1 ]; then
            # 删除 rootfs 下子卷；按逆序删除，避免父子卷依赖导致删除失败
            btrfs subvolume list -o /mnt/rootfs \
              | cut -d ' ' -f 9- \
              | sort -r \
              | while read -r subvolume; do
                [ -z "$subvolume" ] && continue

                case "$subvolume" in
                  /*|*".."*)
                    echo "rollback: skip unsafe subvolume path: $subvolume" >&2
                    continue
                    ;;
                esac

                echo "deleting /''$subvolume subvolume..."
                btrfs subvolume delete "/mnt/rootfs/''$subvolume"
              done

            echo "clearing /mnt/rootfs content..."
            find /mnt/rootfs -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
          else
            # 仅当 rootfs 子卷不存在时，短暂挂载顶层创建 rootfs（不挂载 rootfs 本身）
            mount -o subvolid=5 "$disk" /mnt
            echo "rollback: rootfs subvolume not found, creating it from top-level..."
            btrfs subvolume create /mnt/rootfs
          fi
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
