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
                        "commit=120"
                        "ssd_spread"
                      ]
                    else
                      [
                        "noatime"
                        "compress-force=zstd"
                        "space_cache=v2"
                        "commit=60"
                        "ssd_spread"
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
          # 等待 udev 完成设备节点与 by-label/by-partlabel 符号链接创建
          udevadm settle

          mkdir -p /mnt

          # 移除 -t btrfs，让内置的 mount 自动推断，减少对外部 helper 的依赖
          mount /dev/disk/by-partlabel/NIXOS /mnt \
            || mount /dev/disk/by-label/NIXOS /mnt

          if [ -e /mnt/rootfs ]; then
            # 核心修改：使用 Bash 内置的 read 替代 cut 命令，彻底消除对 coreutils 的依赖
            # btrfs subvolume list 输出的第9列是路径，我们用 _ 跳过前8列
            btrfs subvolume list -o /mnt/rootfs \
              | while read -r _ _ _ _ _ _ _ _ subvolume; do
                echo "deleting /''$subvolume subvolume..."
                btrfs subvolume delete "/mnt/''$subvolume"
              done

            echo "deleting /rootfs subvolume..."
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
