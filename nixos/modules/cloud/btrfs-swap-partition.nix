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
    boot.growPartition = lib.mkForce false;
    zramSwap.enable = lib.mkForce false;

    swapDevices = [
      {
        device = swapDevice;
        options = [ "nofail" ];
      }
    ];

    boot.initrd.systemd.storePaths = [
      pkgs.btrfs-progs
      pkgs.gawk
      pkgs.gptfdisk
      pkgs.parted
      pkgs.util-linux
    ];

    boot.initrd.systemd.services.cloud-btrfs-swap-partition = {
      description = "Expand the root Btrfs partition and create swap if needed";
      wantedBy = [ "initrd.target" ];
      before = [ "sysroot.mount" ];
      after = [ "dev-disk-by\\x2dpartlabel-NIXOS.device" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig.Type = "oneshot";
      script = ''
        set -eu
        echo "cloud-btrfs-swap-partition: start"
        set -x

        if [ -e "${swapDevice}" ]; then
          echo "cloud-btrfs-swap-partition: swap already exists, skipping"
          exit 0
        fi

        if [ ! -e "${rootDevice}" ]; then
          echo "cloud-btrfs-swap-partition: root partition not found, skipping"
          exit 0
        fi

        root_disk_name="$(${pkgs.util-linux}/bin/lsblk -no PKNAME "${rootDevice}" | head -n1 | tr -d '[:space:]')"
        root_part_name="$(${pkgs.util-linux}/bin/lsblk -no KNAME  "${rootDevice}" | head -n1 | tr -d '[:space:]')"
        root_partnum="$(${pkgs.util-linux}/bin/lsblk -no PARTN  "${rootDevice}" | head -n1 | tr -d '[:space:]')"

        if [ -z "$root_disk_name" ] || [ -z "$root_part_name" ] || [ -z "$root_partnum" ]; then
          echo "cloud-btrfs-swap-partition: cannot resolve partition geometry, skipping"
          exit 0
        fi

        root_disk="/dev/$root_disk_name"
        root_disk_sysfs="/sys/class/block/$root_disk_name"
        root_part_sysfs="/sys/class/block/$root_disk_name/$root_part_name"

        root_start_sectors="$(cat "$root_part_sysfs/start")"
        root_size_sectors="$(cat "$root_part_sysfs/size")"
        disk_size_sectors="$(cat "$root_disk_sysfs/size")"
        sector_size="$(cat "$root_disk_sysfs/queue/logical_block_size")"

        root_current_end_sector=$((root_start_sectors + root_size_sectors - 1))
        last_usable_sector=$((disk_size_sectors - 34))

        next_part_start="$(${pkgs.util-linux}/bin/lsblk -nrpo TYPE,START "$root_disk" \
          | ${pkgs.gawk}/bin/awk -v cur="$root_current_end_sector" \
                '$1=="part" && $2>cur { if (min == "" || $2 < min) min = $2 } END { print min }')"
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
          if ! ${pkgs.gptfdisk}/bin/sgdisk -e "$root_disk"; then
            echo "cloud-btrfs-swap-partition: GPT fix failed, skipping"
            exit 0
          fi
          ${pkgs.parted}/bin/partprobe "$root_disk" || true
          ${pkgs.systemd}/bin/udevadm settle || true

          echo "cloud-btrfs-swap-partition: expanding root partition to sector $free_end_sector"
          if ! ${pkgs.gptfdisk}/bin/sgdisk \
            --delete="$root_partnum" \
            --new="$root_partnum:$root_start_sectors:$free_end_sector" \
            --typecode="$root_partnum:8300" \
            --change-name="$root_partnum:${rootPartitionLabel}" \
            "$root_disk"; then
            echo "cloud-btrfs-swap-partition: root expansion failed, skipping"
            exit 0
          fi
          ${pkgs.parted}/bin/partprobe "$root_disk" || true
          ${pkgs.systemd}/bin/udevadm settle || true
        else
          echo "cloud-btrfs-swap-partition: root already fills the disk, skipping expand"
        fi

        btrfs_mount="/btrfs_tmp"
        mkdir -p "$btrfs_mount"
        if ! ${pkgs.util-linux}/bin/mount -t btrfs -o subvolid=5 "${rootDevice}" "$btrfs_mount"; then
          echo "cloud-btrfs-swap-partition: btrfs mount failed"
          exit 0
        fi

        if [ "$need_expand" = "1" ]; then
          echo "cloud-btrfs-swap-partition: expanding btrfs to fill the partition"
          if ! ${pkgs.btrfs-progs}/bin/btrfs filesystem resize max "$btrfs_mount"; then
            echo "cloud-btrfs-swap-partition: btrfs expand failed"
            ${pkgs.util-linux}/bin/umount "$btrfs_mount" || true
            exit 0
          fi
          ${pkgs.btrfs-progs}/bin/btrfs filesystem sync "$btrfs_mount" || true
          sync
        fi

        ram_kb="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo)"
        ram_bytes=$((ram_kb * 1024))
        total_bytes=$(((free_end_sector - root_start_sectors + 1) * sector_size))
        reserve_bytes=${toString rootReserveBytes}

        min_dev_size_bytes="$(${pkgs.btrfs-progs}/bin/btrfs inspect-internal min-dev-size "$btrfs_mount" 2>/dev/null | ${pkgs.gawk}/bin/awk '/^[0-9]+/ { print $1; exit }')"
        if [ "$min_dev_size_bytes" -le 0 ]; then
          echo "cloud-btrfs-swap-partition: cannot read btrfs min-dev-size; done without swap"
          ${pkgs.util-linux}/bin/umount "$btrfs_mount" || true
          exit 0
        fi

        lower_root_bytes=$((min_dev_size_bytes + 1024 * 1024 * 1024))
        lower_root_bytes=$(((lower_root_bytes + 1048575) / 1048576 * 1048576))

        max_swap_bytes=$((total_bytes - lower_root_bytes))
        if [ "$max_swap_bytes" -le 0 ]; then
          echo "cloud-btrfs-swap-partition: no room for swap (min-dev-size=''${min_dev_size_bytes}B, reserve=''${reserve_bytes}B, total=''${total_bytes}B); root stays expanded"
          ${pkgs.util-linux}/bin/umount "$btrfs_mount" || true
          exit 0
        fi

        desired_swap_bytes="$ram_bytes"
        if [ "$desired_swap_bytes" -gt "$max_swap_bytes" ]; then
          desired_swap_bytes="$max_swap_bytes"
        fi

        target_root_bytes=$((total_bytes - desired_swap_bytes))
        if [ "$target_root_bytes" -lt "$lower_root_bytes" ]; then
          target_root_bytes="$lower_root_bytes"
        fi
        target_root_bytes=$(((target_root_bytes + 1048575) / 1048576 * 1048576))
        if [ "$target_root_bytes" -gt "$total_bytes" ]; then
          target_root_bytes="$total_bytes"
        fi

        planned_root_bytes="$target_root_bytes"
        planned_swap_bytes=$((total_bytes - planned_root_bytes))
        planned_swap_mib=$((planned_swap_bytes / 1048576))

        if [ "$planned_swap_mib" -le 0 ]; then
          echo "cloud-btrfs-swap-partition: no room for swap after 1 GiB safety margin; root stays expanded"
          ${pkgs.util-linux}/bin/umount "$btrfs_mount" || true
          exit 0
        fi

        planned_swap_bytes=$((planned_swap_mib * 1048576))
        planned_swap_sectors=$((planned_swap_bytes / sector_size))
        planned_root_new_end=$((free_end_sector - planned_swap_sectors))
        planned_swap_start=$((planned_root_new_end + 1))

        echo "cloud-btrfs-swap-partition: trying root=''${planned_root_bytes}B swap=''${planned_swap_mib} MiB"
        if ! ${pkgs.btrfs-progs}/bin/btrfs filesystem resize -''${planned_swap_mib}m "$btrfs_mount"; then
          echo "cloud-btrfs-swap-partition: btrfs resize failed; no swap will be created"
          ${pkgs.util-linux}/bin/umount "$btrfs_mount" || true
          exit 0
        fi

        echo "cloud-btrfs-swap-partition: creating swap partition"
        if ! ${pkgs.gptfdisk}/bin/sgdisk \
          --new="$((root_partnum + 1)):''${planned_swap_start}:$free_end_sector" \
          --typecode="$((root_partnum + 1)):8200" \
          --change-name="$((root_partnum + 1)):${swapPartitionLabel}" \
          "$root_disk"; then
          echo "cloud-btrfs-swap-partition: swap partition creation failed"
          ${pkgs.util-linux}/bin/umount "$btrfs_mount" || true
          exit 0
        fi
        ${pkgs.parted}/bin/partprobe "$root_disk" || true
        ${pkgs.systemd}/bin/udevadm settle || true

        if ! ${pkgs.util-linux}/bin/mkswap -L "${swapPartitionLabel}" "${swapDevice}"; then
          echo "cloud-btrfs-swap-partition: mkswap failed"
          ${pkgs.util-linux}/bin/umount "$btrfs_mount" || true
          exit 0
        fi

        if ! ${pkgs.util-linux}/bin/swapoff -a 2>/dev/null; then
          true
        fi
        ${pkgs.util-linux}/bin/swapon "${swapDevice}" || true

        ${pkgs.util-linux}/bin/umount "$btrfs_mount" || true
        echo "cloud-btrfs-swap-partition: done"
      '';
    };
  };
}
