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
                        "compress=no"
                        "space_cache=v2"
                        "commit=300"
                        "ssd_spread"
                        "thread_pool=1"
                      ]
                    else
                      [
                        "noatime"
                        "compress=no"
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
                  "/swap" = {
                    mountpoint = "/swap";
                    mountOptions = [
                      "noatime"
                      "nodatacow"
                      "commit=300"
                      "thread_pool=1"
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
      # 禁用 systemd initrd，使用传统 bash initrd
      # （postDeviceCommands 在 systemd initrd 下写法不同）
      systemd.enable = lib.mkForce false;

      # --------------------------------------------------------------------------
      # impermanence（无状态根文件系统）：每次启动时重置 / 分区。
      #
      # 实现原理：
      #   - / 挂载的是 btrfs subvolume "rootfs"
      #   - 每次 stage 1 启动时，先把旧的 rootfs subvolume 完整删掉，
      #     再创建一个全新的空 subvolume，系统启动后 / 就是干净状态
      #   - 需要持久化的数据（/nix /persist /boot）放在独立 subvolume，
      #     不受此操作影响
      #
      # 注意：此脚本通过 lib.mkAfter 追加到 postDeviceCommands 末尾，
      # 必须在 hardware-configuration.nix 的 swap-migration 函数执行完
      # 之后才运行。正因为如此，swap-migration 用函数包裹（return 0
      # 只退出函数），否则会提前结束整个脚本导致这里永远不执行。
      # --------------------------------------------------------------------------
      postDeviceCommands = lib.mkAfter ''
        # 等待 udev 完成，确保 by-partlabel 符号链接已创建
        echo "disko: waiting for udev to settle..."
        udevadm settle || true
        echo "disko: creating/resetting rootfs subvolume on ${config.fileSystems."/".device}"
        mkdir -p /btrfs_tmp
        # 用 subvolid=5 挂载 btrfs 根卷（绕过 subvolume 路由，看到所有子卷）
        if ! mount -t btrfs -o subvolid=5 ${config.fileSystems."/".device} /btrfs_tmp; then
          echo "disko: ERROR - failed to mount btrfs root, bailing out"
        else
          if btrfs subvolume show /btrfs_tmp/rootfs > /dev/null 2>&1; then
            # rootfs subvolume 存在：先递归删除其子卷，再删除本身
            btrfs subvolume list -o /btrfs_tmp/rootfs \
              | cut -d ' ' -f 9- \
              | sort -r \
              | while read -r subvolume; do
                [ -z "$subvolume" ] && continue
                case "$subvolume" in
                  /*|*".."*) continue ;;   # 安全检查，跳过绝对路径和含 .. 的路径
                esac
                btrfs subvolume delete "/btrfs_tmp/$subvolume"
              done
            btrfs subvolume delete /btrfs_tmp/rootfs
          elif [ -e /btrfs_tmp/rootfs ]; then
            # 存在同名普通目录（异常情况），直接删除
            rm -rf /btrfs_tmp/rootfs
          fi

          # 创建全新的空 rootfs subvolume，stage 2 将把 / 挂载到这里
          btrfs subvolume create /btrfs_tmp/rootfs
          umount /btrfs_tmp
          echo "disko: rootfs subvolume ready"
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
