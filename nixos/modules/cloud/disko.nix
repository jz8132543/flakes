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
    ./disko-image-builder.nix
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
                  btrfsOptions = [
                    "noatime"
                    "compress=zstd:1"
                    "space_cache=v2"
                    "commit=300"
                    "ssd_spread"
                    "thread_pool=1"
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
                  # "/swap" = {
                  #   mountpoint = "/swap";
                  #   mountOptions = [
                  #     "noatime"
                  #     "nodatacow"
                  #     "commit=300"
                  #     "thread_pool=1"
                  #   ];
                  # };
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
    initrd.systemd.storePaths = [
      pkgs.btrfs-progs
      pkgs.coreutils
      pkgs.util-linux
    ];
  };

  boot.initrd.systemd.services.disko-rootfs-reset = {
    description = "Reset the rootfs Btrfs subvolume before the real root mounts";
    wantedBy = [ "initrd.target" ];
    before = [ "sysroot.mount" ];
    after = [ "dev-disk-by\\x2dpartlabel-NIXOS.device" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig.Type = "oneshot";
    script = ''
      set -eu

      root_device=${lib.escapeShellArg config.fileSystems."/".device}

      # Wait for udev so the by-partlabel device node is ready.
      echo "disko: waiting for udev to settle..."
      ${pkgs.systemd}/bin/udevadm settle || true
      echo "disko: creating/resetting rootfs subvolume on ${config.fileSystems."/".device}"
      mkdir -p /btrfs_tmp
      # Mount the Btrfs top-level subvolume so we can manage all subvolumes.
      if ! ${pkgs.util-linux}/bin/mount -t btrfs -o subvolid=5 "$root_device" /btrfs_tmp; then
        echo "disko: ERROR - failed to mount btrfs root, bailing out"
      else
        if ${pkgs.btrfs-progs}/bin/btrfs subvolume show /btrfs_tmp/rootfs > /dev/null 2>&1; then
          ${pkgs.btrfs-progs}/bin/btrfs subvolume list -o /btrfs_tmp/rootfs \
            | ${pkgs.coreutils}/bin/cut -d ' ' -f 9- \
            | ${pkgs.coreutils}/bin/sort -r \
            | while read -r subvolume; do
              [ -z "$subvolume" ] && continue
              case "$subvolume" in
                /*|*".."*) continue ;;
              esac
              ${pkgs.btrfs-progs}/bin/btrfs subvolume delete "/btrfs_tmp/$subvolume"
            done
          ${pkgs.btrfs-progs}/bin/btrfs subvolume delete /btrfs_tmp/rootfs
        elif [ -e /btrfs_tmp/rootfs ]; then
          rm -rf /btrfs_tmp/rootfs
        fi

        ${pkgs.btrfs-progs}/bin/btrfs subvolume create /btrfs_tmp/rootfs
        ${pkgs.util-linux}/bin/umount /btrfs_tmp
        echo "disko: rootfs subvolume ready"
      fi
    '';
  };

  # 自动化脚本：启动时动态对指定目录禁用压缩
  systemd.services.btrfs-disable-specific-compression = {
    description = "Disable Btrfs compression on /persist and /rootfs for new files";

    # 确保在所有本地文件系统挂载完成后再执行
    after = [ "local-fs.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;

      # 使用 Shell 脚本安全包裹，防止路径不存在时服务报错
      ExecStart = pkgs.writeShellScript "btrfs-disable-comp" ''
        # 1. 处理 /persist 分区
        if [ -d "/persist" ]; then
          echo "Disabling compression on /persist..."
          ${pkgs.btrfs-progs}/bin/btrfs property set /persist compression none
        fi

        # 2. 处理 /rootfs 分区
        if [ -d "/rootfs" ]; then
          echo "Disabling compression on /rootfs..."
          ${pkgs.btrfs-progs}/bin/btrfs property set /rootfs compression none
        fi
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
