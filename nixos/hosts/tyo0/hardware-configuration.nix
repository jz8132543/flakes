{
  modulesPath,
  lib,
  pkgs,
  ...
}:
let
  rootPartitionLabel = "NIXOS";
  swapPartitionLabel = "SWAP";
  rootReserveBytes = 1024 * 1024 * 1024;
in
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = [
    "ata_piix"
    "uhci_hcd"
    "virtio_pci"
    "sr_mod"
    "virtio_blk"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # Basic networking - DHCP by default
  networking.useDHCP = true;

  # Setup the disk for deployment (assume /dev/vda for qemu virtio_blk)
  # Though the actual format etc is done by dd over the raw image.
  utils.disk = "/dev/vda";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  boot.growPartition = lib.mkForce false;
  # boot.consoleLogLevel = 7;
  # boot.initrd.verbose = true;
  # boot.kernelParams = [
  #   "console=ttyS0,115200n8"
  #   "loglevel=7"
  #   "ignore_loglevel"
  # ];
  # boot.loader.grub.extraConfig = ''
  #   serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
  #   terminal_input serial console
  #   terminal_output serial console
  # '';
  swapDevices = [
    {
      device = "/dev/disk/by-partlabel/SWAP";
      # SWAP partition is created dynamically by the initrd migration script.
      # On first boot the partition may not exist yet; nofail prevents a
      # fatal stage-2 error in that case.
      options = [ "nofail" ];
    }
  ];

  boot.initrd.extraUtilsCommands = ''
    copy_bin_and_libs ${pkgs.parted}/bin/parted
    copy_bin_and_libs ${pkgs.util-linux}/bin/blockdev
    copy_bin_and_libs ${pkgs.util-linux}/bin/lsblk
    copy_bin_and_libs ${pkgs.util-linux}/bin/mkswap
    copy_bin_and_libs ${pkgs.parted}/bin/partprobe
    copy_bin_and_libs ${pkgs.gptfdisk}/bin/sgdisk
    copy_bin_and_libs ${pkgs.btrfs-progs}/bin/btrfs
  '';

  # --------------------------------------------------------------------------
  # tyo0-disk-migration: 一次性 initrd 脚本，在系统首次启动时完成磁盘布局调整。
  #
  # 背景：镜像构建时 NIXOS 分区只有 6G，部署到真实磁盘（通常 10G+）后
  # 剩余空间未被利用；本脚本负责把这些空间分配给 NIXOS 本身和 swap。
  # 即使 NIXOS 分区已被 growPartition 扩展到磁盘末尾，仍需从末尾切出 swap。
  #
  # 执行流程（分两个阶段）：
  #
  #   阶段一：若 NIXOS 后有空闲空间则扩展（否则跳过）
  #     1. 幂等检查：SWAP 分区已存在 → 说明已迁移，直接跳过
  #     2. 读取磁盘几何，计算 NIXOS 末尾到可用空间末尾的扇区范围
  #     3a. 若有空闲：修复 GPT 备份头 → 扩展 NIXOS → btrfs resize max
  #     3b. 若 NIXOS 已到磁盘末尾：跳过扩展，直接进入阶段二
  #
  #   阶段二：从末尾切出 SWAP 分区（两种情况都执行）
  #     4. 挂载 btrfs，读取实际占用字节数（非分区大小）
  #     5. 计算 swap 大小：
  #          swap = min(RAM 大小, 分区总量 - btrfs已用 - 1GiB预留)
  #          若结果 ≤ 0 → 不建 swap，脚本结束
  #     6. btrfs shrink → 重写 GPT（NIXOS 缩小 + 新增 SWAP） → mkswap
  #
  # 注意：整个逻辑包在函数里，'return 0' 只退出函数，不影响
  # disko.nix 通过 lib.mkAfter 追加的 impermanence（重建 rootfs）代码。
  # --------------------------------------------------------------------------
  boot.initrd.postDeviceCommands = lib.mkAfter ''
    tyo0_disk_migration() {
      echo "tyo0-disk-migration: start"
      set -x

      swap_device="/dev/disk/by-partlabel/${swapPartitionLabel}"
      root_device="/dev/disk/by-partlabel/${rootPartitionLabel}"

      # ── 幂等检查 ──────────────────────────────────────────────────────────
      if [ -e "$swap_device" ]; then
        echo "tyo0-disk-migration: already migrated (SWAP exists), skipping"
        return 0
      fi

      if [ ! -e "$root_device" ]; then
        echo "tyo0-disk-migration: NIXOS partition not found, skipping"
        return 0
      fi

      # ── 读取磁盘几何信息 ──────────────────────────────────────────────────
      root_disk_name="$(lsblk -no PKNAME "$root_device" | head -n1 | tr -d '[:space:]')"
      root_part_name="$(lsblk -no KNAME  "$root_device" | head -n1 | tr -d '[:space:]')"
      root_partnum="$(  lsblk -no PARTN  "$root_device" | head -n1 | tr -d '[:space:]')"

      if [ -z "$root_disk_name" ] || [ -z "$root_part_name" ] || [ -z "$root_partnum" ]; then
        echo "tyo0-disk-migration: cannot resolve partition geometry, skipping"
        return 0
      fi

      root_disk="/dev/$root_disk_name"
      root_disk_sysfs="/sys/class/block/$root_disk_name"
      root_part_sysfs="/sys/class/block/$root_disk_name/$root_part_name"

      root_start_sectors="$(cat "$root_part_sysfs/start")"
      root_size_sectors="$( cat "$root_part_sysfs/size")"
      disk_size_sectors="$(  cat "$root_disk_sysfs/size")"
      sector_size="$(        cat "$root_disk_sysfs/queue/logical_block_size")"

      root_current_end_sector=$((root_start_sectors + root_size_sectors - 1))
      # GPT 在磁盘末尾保留 34 个扇区存备份分区表
      last_usable_sector=$((disk_size_sectors - 34))

      # ── 阶段一：计算可用扇区范围，决定是否需要扩展 NIXOS ─────────────────
      # 若 NIXOS 后面紧跟另一个分区，可用范围截止到该分区的前一个扇区；
      # 否则可用到磁盘最后可用扇区（可能等于 NIXOS 末尾，即不需扩展的情况）。
      next_part_start="$(lsblk -nrpo TYPE,START "$root_disk" \
        | awk -v cur="$root_current_end_sector" \
              '$1=="part" && $2>cur { print $2; exit }')"
      if [ -n "$next_part_start" ]; then
        free_end_sector=$((next_part_start - 1))
      else
        free_end_sector="$last_usable_sector"
      fi

      # free_end_sector 是本轮能使用的最后一个扇区。
      # 若大于 NIXOS 当前末尾 → 需要扩展；否则 NIXOS 已到磁盘末尾，跳过扩展。
      if [ "$free_end_sector" -gt "$root_current_end_sector" ]; then
        need_expand=1
      else
        need_expand=0
        # 已到末尾：把 free_end_sector 对齐到 NIXOS 当前末尾，swap 从这里往前切
        free_end_sector="$root_current_end_sector"
      fi

      # ── 若有空闲空间：修复 GPT 备份头 + 扩展 NIXOS 分区 ─────────────────
      if [ "$need_expand" = "1" ]; then
        # 磁盘从小盘 dd 到大盘后，GPT 备份头仍在旧位置；sgdisk -e 将其移到末尾
        echo "tyo0-disk-migration: fixing GPT backup header"
        if ! sgdisk -e "$root_disk"; then
          echo "tyo0-disk-migration: GPT fix failed, skipping"
          return 0
        fi
        partprobe "$root_disk" || true
        udevadm settle || true

        echo "tyo0-disk-migration: expanding NIXOS to sector $free_end_sector"
        if ! sgdisk \
          --delete="$root_partnum" \
          --new="$root_partnum:$root_start_sectors:$free_end_sector" \
          --typecode="$root_partnum:8300" \
          --change-name="$root_partnum:${rootPartitionLabel}" \
          "$root_disk"; then
          echo "tyo0-disk-migration: NIXOS expansion failed, skipping"
          return 0
        fi
        partprobe "$root_disk" || true
        udevadm settle || true
      else
        echo "tyo0-disk-migration: NIXOS already fills disk, skipping expand"
      fi

      # ── 挂载 btrfs（两种情况都需要）─────────────────────────────────────
      btrfs_mount="/btrfs_tmp"
      mkdir -p "$btrfs_mount"
      if ! mount -t btrfs -o subvolid=5 "$root_device" "$btrfs_mount"; then
        echo "tyo0-disk-migration: btrfs mount failed"
        return 0
      fi

      if [ "$need_expand" = "1" ]; then
        echo "tyo0-disk-migration: expanding btrfs to fill partition"
        if ! btrfs filesystem resize max "$btrfs_mount"; then
          echo "tyo0-disk-migration: btrfs expand failed"
          umount "$btrfs_mount" || true
          return 0
        fi
      fi

      # ── 阶段二：计算 swap 大小 ───────────────────────────────────────────
      # 读取 btrfs 实际占用字节（Used，而非 Device size）
      used_bytes="$(btrfs filesystem usage -b "$btrfs_mount" \
        | awk '$1=="Used:" { print $2; exit }')"
      if [ -z "$used_bytes" ]; then
        echo "tyo0-disk-migration: cannot read btrfs usage; done without swap"
        umount "$btrfs_mount" || true
        return 0
      fi

      # 从 /proc/meminfo 取 RAM 大小（KiB → 字节），用于限制 swap 上限
      ram_kb="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo)"
      ram_bytes=$((ram_kb * 1024))

      # 可用分区总字节：从 NIXOS 起始扇区到 free_end_sector（扩展后或原始大小）
      total_bytes=$(((free_end_sector - root_start_sectors + 1) * sector_size))

      # swap 候选大小 = 总容量 - btrfs实际用量 - 1GiB预留
      reserve_bytes=${toString rootReserveBytes}
      swap_candidate_bytes=$((total_bytes - used_bytes - reserve_bytes))

      if [ "$swap_candidate_bytes" -le 0 ]; then
        # btrfs 已用量 + 预留 > 总容量，没有余量给 swap
        echo "tyo0-disk-migration: no room for swap (btrfs used ''${used_bytes} B + ''${reserve_bytes} B reserve >= ''${total_bytes} B); NIXOS expanded only"
        umount "$btrfs_mount" || true
        return 0
      fi

      # swap 上限取 RAM 大小；swap 大小对齐到 MiB 边界
      if [ "$swap_candidate_bytes" -gt "$ram_bytes" ]; then
        swap_bytes="$ram_bytes"
      else
        swap_bytes="$swap_candidate_bytes"
      fi
      swap_mib=$((swap_bytes / (1024 * 1024)))

      if [ "$swap_mib" -le 0 ]; then
        echo "tyo0-disk-migration: swap < 1 MiB after alignment; NIXOS expanded only"
        umount "$btrfs_mount" || true
        return 0
      fi

      # 对齐后的精确字节数和扇区数
      swap_bytes=$((swap_mib * 1024 * 1024))
      swap_sectors=$((swap_bytes / sector_size))
      nixos_new_end=$((free_end_sector - swap_sectors))
      swap_start=$((nixos_new_end + 1))

      # ── btrfs 缩回（只做一次 resize）────────────────────────────────────
      echo "tyo0-disk-migration: shrinking btrfs by ''${swap_mib} MiB for swap"
      if ! btrfs filesystem resize -''${swap_mib}m "$btrfs_mount"; then
        echo "tyo0-disk-migration: btrfs shrink failed; NIXOS remains expanded, no swap"
        umount "$btrfs_mount" || true
        return 0
      fi
      umount "$btrfs_mount"

      # ── 一次性重写 GPT：NIXOS 缩小 + 新建 SWAP ───────────────────────────
      echo "tyo0-disk-migration: rewriting GPT (NIXOS 0-''${nixos_new_end}, SWAP ''${swap_start}-''${free_end_sector})"
      if ! sgdisk \
        --delete="$root_partnum" \
        --new="$root_partnum:$root_start_sectors:$nixos_new_end" \
        --typecode="$root_partnum:8300" \
        --change-name="$root_partnum:${rootPartitionLabel}" \
        --new="0:$swap_start:$free_end_sector" \
        --typecode="0:8200" \
        --change-name="0:${swapPartitionLabel}" \
        "$root_disk"; then
        echo "tyo0-disk-migration: GPT rewrite failed"
        return 0
      fi
      partprobe "$root_disk" || true
      udevadm settle || true

      # ── 格式化 swap 分区 ──────────────────────────────────────────────────
      if [ -e "$swap_device" ]; then
        echo "tyo0-disk-migration: formatting swap (''${swap_mib} MiB)"
        mkswap -L "${swapPartitionLabel}" "$swap_device"
      fi

      echo "tyo0-disk-migration: done"
    }
    # 调用迁移函数（函数内的 return 0 不会影响本脚本后续代码）
    tyo0_disk_migration
  '';
  nix.gc.automatic = lib.mkForce true;
}
