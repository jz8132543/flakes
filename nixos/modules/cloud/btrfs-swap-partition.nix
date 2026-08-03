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
      description = "first-boot root (Btrfs/ext4) expansion plus swap partition migration";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.growPartition = lib.mkForce false;
    zramSwap.enable = lib.mkForce false;

    swapDevices = [
      {
        device = swapDevice;
        options = [
          "nofail"
          "x-systemd.device-timeout=5s"
        ];
      }
    ];

    boot.initrd.systemd.storePaths = [
      pkgs.btrfs-progs
      pkgs.coreutils
      pkgs.e2fsprogs
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gptfdisk
      pkgs.parted
      pkgs.util-linux
    ];

    boot.initrd.systemd.services.cloud-btrfs-swap-partition = {
      description = "Expand the root partition (Btrfs/ext4) and create swap if needed";
      wantedBy = [ "initrd.target" ];
      before = [
        "sysroot.mount"
        "systemd-fsck@dev-disk-by\\x2dpartlabel-NIXOS.service"
        "disko-rootfs-reset.service"
      ];
      after = [ "dev-disk-by\\x2dpartlabel-NIXOS.device" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "120s";
        SuccessExitStatus = [
          "0"
          "1"
          "2"
          "3"
          "4"
          "5"
          "6"
          "7"
          "8"
          "255"
        ];
      };
      script = ''
        set -u
        echo "cloud-btrfs-swap-partition: start"

        cleanup_and_exit() {
          local status=$1
          if [ "$status" != "0" ]; then
            echo "cloud-btrfs-swap-partition: warning - non-fatal error occurred (status $status), skipping swap/resize to ensure boot continues safely"
          fi
          ${pkgs.util-linux}/bin/umount /btrfs_tmp 2>/dev/null || true
          exit 0
        }

        trap 'cleanup_and_exit 0' EXIT
        trap 'cleanup_and_exit $?' ERR

        set -e
        set -x

        if [ -e "${swapDevice}" ]; then
          echo "cloud-btrfs-swap-partition: swap already exists, skipping"
          exit 0
        fi

        if [ ! -e "${rootDevice}" ]; then
          echo "cloud-btrfs-swap-partition: root partition not found, skipping"
          exit 0
        fi

        root_disk_name="$(${pkgs.util-linux}/bin/lsblk -no PKNAME "${rootDevice}" 2>/dev/null || true | head -n1 | tr -d '[:space:]')"
        root_part_name="$(${pkgs.util-linux}/bin/lsblk -no KNAME "${rootDevice}" 2>/dev/null || true | head -n1 | tr -d '[:space:]')"
        root_partnum="$(${pkgs.util-linux}/bin/lsblk -no PARTN "${rootDevice}" 2>/dev/null || true | head -n1 | tr -d '[:space:]')"
        fstype="$(${pkgs.util-linux}/bin/lsblk -no FSTYPE "${rootDevice}" 2>/dev/null || true | head -n1 | tr -d '[:space:]')"

        if [ -z "$root_disk_name" ] || [ -z "$root_part_name" ] || [ -z "$root_partnum" ]; then
          echo "cloud-btrfs-swap-partition: cannot resolve partition geometry, skipping"
          exit 0
        fi

        if [ "$fstype" != "btrfs" ] && [ "$fstype" != "ext4" ]; then
          echo "cloud-btrfs-swap-partition: unsupported fstype '$fstype', skipping"
          exit 0
        fi

        root_disk="/dev/$root_disk_name"
        if ${pkgs.util-linux}/bin/lsblk -no PARTLABEL "$root_disk" 2>/dev/null || true | ${pkgs.gnugrep}/bin/grep -Fqx "${swapPartitionLabel}"; then
          echo "cloud-btrfs-swap-partition: swap partition already found on disk, skipping"
          exit 0
        fi

        root_disk_sysfs="/sys/class/block/$root_disk_name"
        root_part_sysfs="/sys/class/block/$root_part_name"
        if [ ! -e "$root_part_sysfs/start" ]; then
          root_part_sysfs="/sys/class/block/$root_disk_name/$root_part_name"
        fi

        if [ ! -f "$root_part_sysfs/start" ] || [ ! -f "$root_part_sysfs/size" ] || [ ! -f "$root_disk_sysfs/size" ]; then
          echo "cloud-btrfs-swap-partition: sysfs geometry files missing, skipping"
          exit 0
        fi

        root_start_sectors="$(cat "$root_part_sysfs/start" 2>/dev/null || echo 0)"
        root_size_sectors="$(cat "$root_part_sysfs/size" 2>/dev/null || echo 0)"
        disk_size_sectors="$(cat "$root_disk_sysfs/size" 2>/dev/null || echo 0)"
        sector_size="$(cat "$root_disk_sysfs/queue/logical_block_size" 2>/dev/null || echo 512)"

        if [ "$root_start_sectors" -le 0 ] || [ "$root_size_sectors" -le 0 ] || [ "$disk_size_sectors" -le 0 ]; then
          echo "cloud-btrfs-swap-partition: invalid sector counts, skipping"
          exit 0
        fi

        root_current_end_sector=$((root_start_sectors + root_size_sectors - 1))
        last_usable_sector=$((disk_size_sectors - 34))

        next_part_start="$(${pkgs.util-linux}/bin/lsblk -nrpo TYPE,START "$root_disk" 2>/dev/null || true \
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
          ${pkgs.gptfdisk}/bin/sgdisk -e "$root_disk" 2>/dev/null || true
          ${pkgs.parted}/bin/partprobe "$root_disk" 2>/dev/null || true
          ${pkgs.systemd}/bin/udevadm settle --timeout=5 2>/dev/null || true

          echo "cloud-btrfs-swap-partition: expanding root partition to sector $free_end_sector"
          if ! ${pkgs.gptfdisk}/bin/sgdisk \
            --delete="$root_partnum" \
            --new="$root_partnum:$root_start_sectors:$free_end_sector" \
            --typecode="$root_partnum:8300" \
            --change-name="$root_partnum:${rootPartitionLabel}" \
            "$root_disk" 2>/dev/null; then
            echo "cloud-btrfs-swap-partition: root expansion failed, skipping"
            exit 0
          fi
          ${pkgs.parted}/bin/partprobe "$root_disk" 2>/dev/null || true
          ${pkgs.systemd}/bin/udevadm settle --timeout=5 2>/dev/null || true
        else
          echo "cloud-btrfs-swap-partition: root already fills the disk, skipping initial expand"
        fi

        btrfs_mount="/btrfs_tmp"
        min_dev_size_bytes=0

        if [ "$fstype" = "btrfs" ]; then
          mkdir -p "$btrfs_mount"
          if ! ${pkgs.util-linux}/bin/mount -t btrfs -o subvolid=5 "${rootDevice}" "$btrfs_mount" 2>/dev/null; then
            echo "cloud-btrfs-swap-partition: btrfs mount failed"
            exit 0
          fi
          if [ "$need_expand" = "1" ]; then
            echo "cloud-btrfs-swap-partition: expanding btrfs to fill the partition"
            if ! ${pkgs.btrfs-progs}/bin/btrfs filesystem resize max "$btrfs_mount" 2>/dev/null; then
              echo "cloud-btrfs-swap-partition: btrfs expand failed"
              ${pkgs.util-linux}/bin/umount "$btrfs_mount" 2>/dev/null || true
              exit 0
            fi
            ${pkgs.btrfs-progs}/bin/btrfs filesystem sync "$btrfs_mount" 2>/dev/null || true
            sync
          fi
          min_dev_size_bytes="$(${pkgs.btrfs-progs}/bin/btrfs inspect-internal min-dev-size "$btrfs_mount" 2>/dev/null || true | ${pkgs.gawk}/bin/awk '/^[0-9]+/ { print $1; exit }')"
        elif [ "$fstype" = "ext4" ]; then
          ${pkgs.e2fsprogs}/bin/e2fsck -f -p "${rootDevice}" 2>/dev/null || true
          block_size="$(${pkgs.e2fsprogs}/bin/dumpe2fs -h "${rootDevice}" 2>/dev/null || true | ${pkgs.gawk}/bin/awk '/^Block size:/ {print $3; exit}')"
          if [ -z "$block_size" ]; then block_size=4096; fi
          min_blocks="$(${pkgs.e2fsprogs}/bin/resize2fs -P "${rootDevice}" 2>/dev/null || true | ${pkgs.gawk}/bin/awk '{for(i=1;i<=NF;i++) if($i~/^[0-9]+$/) {print $i; exit}}')"
          if [ -n "$min_blocks" ] && [ "$min_blocks" -gt 0 ]; then
            min_dev_size_bytes=$((min_blocks * block_size))
          else
            min_dev_size_bytes=$((root_size_sectors * sector_size))
          fi
        fi

        if [ -z "$min_dev_size_bytes" ] || [ "$min_dev_size_bytes" -le 0 ]; then
          echo "cloud-btrfs-swap-partition: cannot read min-dev-size; done without swap"
          if [ "$fstype" = "btrfs" ]; then
            ${pkgs.util-linux}/bin/umount "$btrfs_mount" 2>/dev/null || true
          elif [ "$fstype" = "ext4" ] && [ "$need_expand" = "1" ]; then
            ${pkgs.e2fsprogs}/bin/e2fsck -f -p "${rootDevice}" 2>/dev/null || true
            ${pkgs.e2fsprogs}/bin/resize2fs "${rootDevice}" 2>/dev/null || true
          fi
          exit 0
        fi

        ram_kb="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo 2>/dev/null || echo 0)"
        ram_bytes=$((ram_kb * 1024))
        total_bytes=$(((free_end_sector - root_start_sectors + 1) * sector_size))
        reserve_bytes=${toString rootReserveBytes}

        lower_root_bytes=$((min_dev_size_bytes + 1024 * 1024 * 1024))
        lower_root_bytes=$(((lower_root_bytes + 1048575) / 1048576 * 1048576))

        max_swap_bytes=$((total_bytes - lower_root_bytes))
        if [ "$max_swap_bytes" -le 0 ]; then
          echo "cloud-btrfs-swap-partition: no room for swap (min-dev-size=''${min_dev_size_bytes}B, reserve=''${reserve_bytes}B, total=''${total_bytes}B); root stays expanded"
          if [ "$fstype" = "btrfs" ]; then
            ${pkgs.util-linux}/bin/umount "$btrfs_mount" 2>/dev/null || true
          elif [ "$fstype" = "ext4" ] && [ "$need_expand" = "1" ]; then
            ${pkgs.e2fsprogs}/bin/e2fsck -f -p "${rootDevice}" 2>/dev/null || true
            ${pkgs.e2fsprogs}/bin/resize2fs "${rootDevice}" 2>/dev/null || true
          fi
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
          if [ "$fstype" = "btrfs" ]; then
            ${pkgs.util-linux}/bin/umount "$btrfs_mount" 2>/dev/null || true
          elif [ "$fstype" = "ext4" ] && [ "$need_expand" = "1" ]; then
            ${pkgs.e2fsprogs}/bin/e2fsck -f -p "${rootDevice}" 2>/dev/null || true
            ${pkgs.e2fsprogs}/bin/resize2fs "${rootDevice}" 2>/dev/null || true
          fi
          exit 0
        fi

        planned_swap_bytes=$((planned_swap_mib * 1048576))
        planned_swap_sectors=$((planned_swap_bytes / sector_size))
        planned_root_new_end=$((free_end_sector - planned_swap_sectors))
        planned_swap_start=$((planned_root_new_end + 1))

        echo "cloud-btrfs-swap-partition: trying root=''${planned_root_bytes}B swap=''${planned_swap_mib} MiB"
        if [ "$fstype" = "btrfs" ]; then
          if ! ${pkgs.btrfs-progs}/bin/btrfs filesystem resize -''${planned_swap_mib}m "$btrfs_mount" 2>/dev/null; then
            echo "cloud-btrfs-swap-partition: btrfs resize failed; no swap will be created"
            ${pkgs.util-linux}/bin/umount "$btrfs_mount" 2>/dev/null || true
            exit 0
          fi
          ${pkgs.util-linux}/bin/umount "$btrfs_mount" 2>/dev/null || true
        elif [ "$fstype" = "ext4" ]; then
          block_count="$(${pkgs.e2fsprogs}/bin/dumpe2fs -h "${rootDevice}" 2>/dev/null || true | ${pkgs.gawk}/bin/awk '/^Block count:/ {print $3; exit}')"
          if [ -n "$block_count" ]; then
            current_ext4_bytes=$((block_count * block_size))
            if [ "$current_ext4_bytes" -gt "$planned_root_bytes" ]; then
              echo "cloud-btrfs-swap-partition: shrinking ext4 filesystem from $((current_ext4_bytes / 1048576)) MiB to $((planned_root_bytes / 1048576)) MiB"
              ${pkgs.e2fsprogs}/bin/e2fsck -f -p "${rootDevice}" 2>/dev/null || true
              if ! ${pkgs.e2fsprogs}/bin/resize2fs "${rootDevice}" $((planned_root_bytes / block_size)) 2>/dev/null; then
                echo "cloud-btrfs-swap-partition: ext4 shrink failed; no swap will be created"
                exit 0
              fi
            fi
          fi
        fi

        swap_partnum="$(${pkgs.util-linux}/bin/lsblk -no PARTN "$root_disk" 2>/dev/null || true | ${pkgs.gawk}/bin/awk '/^[0-9]+$/ {used[$1]=1} END {for(i=1;i<=128;i++) if(!used[i]) {print i; exit}}')"
        if [ -z "$swap_partnum" ] || [ "$swap_partnum" -le 0 ]; then
          echo "cloud-btrfs-swap-partition: cannot find free partition number for swap"
          exit 0
        fi

        echo "cloud-btrfs-swap-partition: updating GPT partition table for root (part $root_partnum) and swap (part $swap_partnum)"
        if ! ${pkgs.gptfdisk}/bin/sgdisk \
          --delete="$root_partnum" \
          --new="$root_partnum:$root_start_sectors:$planned_root_new_end" \
          --typecode="$root_partnum:8300" \
          --change-name="$root_partnum:${rootPartitionLabel}" \
          --new="$swap_partnum:$planned_swap_start:$free_end_sector" \
          --typecode="$swap_partnum:8200" \
          --change-name="$swap_partnum:${swapPartitionLabel}" \
          "$root_disk" 2>/dev/null; then
          echo "cloud-btrfs-swap-partition: partition table update failed"
          exit 0
        fi
        ${pkgs.parted}/bin/partprobe "$root_disk" 2>/dev/null || true
        ${pkgs.systemd}/bin/udevadm settle --timeout=5 2>/dev/null || true

        if [ "$fstype" = "ext4" ]; then
          echo "cloud-btrfs-swap-partition: growing ext4 filesystem to fill root partition"
          ${pkgs.e2fsprogs}/bin/e2fsck -f -p "${rootDevice}" 2>/dev/null || true
          if ! ${pkgs.e2fsprogs}/bin/resize2fs "${rootDevice}" 2>/dev/null; then
            echo "cloud-btrfs-swap-partition: ext4 resize failed"
            exit 0
          fi
        elif [ "$fstype" = "btrfs" ]; then
          mkdir -p "$btrfs_mount"
          if ${pkgs.util-linux}/bin/mount -t btrfs -o subvolid=5 "${rootDevice}" "$btrfs_mount" 2>/dev/null; then
            ${pkgs.btrfs-progs}/bin/btrfs filesystem resize max "$btrfs_mount" 2>/dev/null || true
            ${pkgs.btrfs-progs}/bin/btrfs filesystem sync "$btrfs_mount" 2>/dev/null || true
            ${pkgs.util-linux}/bin/umount "$btrfs_mount" 2>/dev/null || true
          fi
        fi

        if ! ${pkgs.util-linux}/bin/mkswap -L "${swapPartitionLabel}" "${swapDevice}" 2>/dev/null; then
          echo "cloud-btrfs-swap-partition: mkswap failed"
          exit 0
        fi

        if ! ${pkgs.util-linux}/bin/swapoff -a 2>/dev/null; then
          true
        fi
        ${pkgs.util-linux}/bin/swapon "${swapDevice}" 2>/dev/null || true

        echo "cloud-btrfs-swap-partition: done"
      '';
    };
  };
}
