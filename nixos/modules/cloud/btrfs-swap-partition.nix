{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.cloud.btrfsSwapPartition;
  rootPartitionLabel = "NIXOS";
  swapPartitionLabel = "SWAP";
  rootReserveBytes = 1024 * 1024 * 1024;
  rootDevice = "/dev/disk/by-partlabel/${rootPartitionLabel}";
  swapDevice = "/dev/disk/by-partlabel/${swapPartitionLabel}";
in
{
  options.cloud.btrfsSwapPartition = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "first-boot Btrfs root expansion plus swap partition migration";
    };
  };

  config = lib.mkIf cfg.enable {
    # Keep the root partition under our control; the migration script expands
    # the partition itself and then rewrites the GPT once the final size is known.
    boot.growPartition = lib.mkForce false;

    # Disk-backed swap replaces zram on hosts that opt into this layout.
    zramSwap.enable = lib.mkForce false;

    swapDevices = [
      {
        device = swapDevice;
        # The first boot may run before the migration script has created SWAP.
        # nofail keeps the missing device from becoming a fatal boot error.
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

    # The script is intentionally conservative:
    # - if SWAP already exists, it does nothing
    # - if the root partition is missing, it does nothing
    # - if the Btrfs usage cannot be read, it keeps the root partition expanded
    #   and skips creating swap rather than risking a broken boot.
    boot.initrd.postDeviceCommands = lib.mkAfter ''
      cloud_btrfs_swap_partition_migration() {
        echo "cloud-btrfs-swap-partition: start"
        set -x

        if [ -e "${swapDevice}" ]; then
          echo "cloud-btrfs-swap-partition: swap already exists, skipping"
          return 0
        fi

        if [ ! -e "${rootDevice}" ]; then
          echo "cloud-btrfs-swap-partition: root partition not found, skipping"
          return 0
        fi

        root_disk_name="$(lsblk -no PKNAME "${rootDevice}" | head -n1 | tr -d '[:space:]')"
        root_part_name="$(lsblk -no KNAME  "${rootDevice}" | head -n1 | tr -d '[:space:]')"
        root_partnum="$(  lsblk -no PARTN  "${rootDevice}" | head -n1 | tr -d '[:space:]')"

        if [ -z "$root_disk_name" ] || [ -z "$root_part_name" ] || [ -z "$root_partnum" ]; then
          echo "cloud-btrfs-swap-partition: cannot resolve partition geometry, skipping"
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
        last_usable_sector=$((disk_size_sectors - 34))

        next_part_start="$(lsblk -nrpo TYPE,START "$root_disk" \
          | awk -v cur="$root_current_end_sector" \
                '$1=="part" && $2>cur { print $2; exit }')"
        if [ -n "$next_part_start" ]; then
          free_end_sector=$((next_part_start - 1))
        else
          free_end_sector="$last_usable_sector"
        fi

        if [ "$free_end_sector" -gt "$root_current_end_sector" ]; then
          need_expand=1
        else
          need_expand=0
          free_end_sector="$root_current_end_sector"
        fi

        if [ "$need_expand" = "1" ]; then
          echo "cloud-btrfs-swap-partition: fixing GPT backup header"
          if ! sgdisk -e "$root_disk"; then
            echo "cloud-btrfs-swap-partition: GPT fix failed, skipping"
            return 0
          fi
          partprobe "$root_disk" || true
          udevadm settle || true

          echo "cloud-btrfs-swap-partition: expanding root partition to sector $free_end_sector"
          if ! sgdisk \
            --delete="$root_partnum" \
            --new="$root_partnum:$root_start_sectors:$free_end_sector" \
            --typecode="$root_partnum:8300" \
            --change-name="$root_partnum:${rootPartitionLabel}" \
            "$root_disk"; then
            echo "cloud-btrfs-swap-partition: root expansion failed, skipping"
            return 0
          fi
          partprobe "$root_disk" || true
          udevadm settle || true
        else
          echo "cloud-btrfs-swap-partition: root already fills the disk, skipping expand"
        fi

        btrfs_mount="/btrfs_tmp"
        mkdir -p "$btrfs_mount"
        if ! mount -t btrfs -o subvolid=5 "${rootDevice}" "$btrfs_mount"; then
          echo "cloud-btrfs-swap-partition: btrfs mount failed"
          return 0
        fi

        if [ "$need_expand" = "1" ]; then
          echo "cloud-btrfs-swap-partition: expanding btrfs to fill the partition"
          if ! btrfs filesystem resize max "$btrfs_mount"; then
            echo "cloud-btrfs-swap-partition: btrfs expand failed"
            umount "$btrfs_mount" || true
            return 0
          fi
          # Flush the resized filesystem before we start changing partition tables.
          btrfs filesystem sync "$btrfs_mount" || true
          sync
        fi

        used_bytes="$(btrfs filesystem usage -b "$btrfs_mount" \
          | awk '$1=="Used:" { print $2; exit }')"
        if [ -z "$used_bytes" ]; then
          echo "cloud-btrfs-swap-partition: cannot read btrfs usage; done without swap"
          umount "$btrfs_mount" || true
          return 0
        fi

        ram_kb="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo)"
        ram_bytes=$((ram_kb * 1024))

        total_bytes=$(((free_end_sector - root_start_sectors + 1) * sector_size))
        reserve_bytes=${toString rootReserveBytes}
        swap_candidate_bytes=$((total_bytes - used_bytes - reserve_bytes))

        if [ "$swap_candidate_bytes" -le 0 ]; then
          echo "cloud-btrfs-swap-partition: no room for swap (used=''${used_bytes}B, reserve=''${reserve_bytes}B, total=''${total_bytes}B); root stays expanded"
          umount "$btrfs_mount" || true
          return 0
        fi

        if [ "$swap_candidate_bytes" -gt "$ram_bytes" ]; then
          swap_bytes="$ram_bytes"
        else
          swap_bytes="$swap_candidate_bytes"
        fi
        swap_mib=$((swap_bytes / (1024 * 1024)))

        if [ "$swap_mib" -le 0 ]; then
          echo "cloud-btrfs-swap-partition: swap < 1 MiB after alignment; root stays expanded"
          umount "$btrfs_mount" || true
          return 0
        fi

        swap_bytes=$((swap_mib * 1024 * 1024))
        swap_sectors=$((swap_bytes / sector_size))
        root_new_end=$((free_end_sector - swap_sectors))
        swap_start=$((root_new_end + 1))

        echo "cloud-btrfs-swap-partition: shrinking btrfs by ''${swap_mib} MiB for swap"
        if ! btrfs filesystem resize -''${swap_mib}m "$btrfs_mount"; then
          echo "cloud-btrfs-swap-partition: btrfs shrink failed; no swap will be created"
          umount "$btrfs_mount" || true
          return 0
        fi
        # Make the shrink durable before rewriting the GPT and creating SWAP.
        btrfs filesystem sync "$btrfs_mount" || true
        sync
        umount "$btrfs_mount"

        echo "cloud-btrfs-swap-partition: rewriting GPT (root 0-''${root_new_end}, swap ''${swap_start}-''${free_end_sector})"
        if ! sgdisk \
          --delete="$root_partnum" \
          --new="$root_partnum:$root_start_sectors:$root_new_end" \
          --typecode="$root_partnum:8300" \
          --change-name="$root_partnum:${rootPartitionLabel}" \
          --new="0:$swap_start:$free_end_sector" \
          --typecode="0:8200" \
          --change-name="0:${swapPartitionLabel}" \
          "$root_disk"; then
          echo "cloud-btrfs-swap-partition: GPT rewrite failed"
          return 0
        fi
        partprobe "$root_disk" || true
        udevadm settle || true

        if [ -e "${swapDevice}" ]; then
          echo "cloud-btrfs-swap-partition: formatting swap (''${swap_mib} MiB)"
          mkswap -L "${swapPartitionLabel}" "${swapDevice}"
          sync
        fi

        echo "cloud-btrfs-swap-partition: done"
      }

      cloud_btrfs_swap_partition_migration
    '';
  };
}
