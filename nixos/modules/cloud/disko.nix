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
    initrd = {
      systemd.enable = lib.mkForce false;
      postDeviceCommands = lib.mkAfter ''
        mkdir -p /btrfs_tmp
        mount -t btrfs -o subvolid=5 ${config.fileSystems."/".device} /btrfs_tmp

        if btrfs subvolume show /btrfs_tmp/rootfs >/dev/null 2>&1; then
          btrfs subvolume list -o /btrfs_tmp/rootfs \
            | cut -d ' ' -f 9- \
            | sort -r \
            | while read -r subvolume; do
              [ -z "$subvolume" ] && continue
              case "$subvolume" in
                /*|*".."*) continue ;;
              esac
              btrfs subvolume delete "/btrfs_tmp/$subvolume"
            done
          btrfs subvolume delete /btrfs_tmp/rootfs
        elif [ -e /btrfs_tmp/rootfs ]; then
          rm -rf /btrfs_tmp/rootfs
        fi

        btrfs subvolume create /btrfs_tmp/rootfs
        umount /btrfs_tmp
      '';
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
