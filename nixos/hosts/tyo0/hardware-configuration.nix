{
  modulesPath,
  lib,
  pkgs,
  ...
}:
let
  rootPartitionLabel = "NIXOS";
  swapPartitionLabel = "SWAP";
  swapPartitionBytes = 1024 * 1024 * 1024;
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
  boot.kernelParams = [ "console=ttyS0,115200n8" ];
  boot.loader.grub.extraConfig = ''
    serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
    terminal_input serial console
    terminal_output serial console
  '';
  swapDevices = [
    {
      device = "/dev/disk/by-partlabel/SWAP";
    }
  ];

  boot.initrd.extraUtilsCommands = ''
    copy_bin_and_libs ${pkgs.parted}/bin/parted
    copy_bin_and_libs ${pkgs.util-linux}/bin/blockdev
    copy_bin_and_libs ${pkgs.util-linux}/bin/lsblk
    copy_bin_and_libs ${pkgs.util-linux}/bin/mkswap
    copy_bin_and_libs ${pkgs.parted}/bin/partprobe
    copy_bin_and_libs ${pkgs.btrfs-progs}/bin/btrfs
  '';

  boot.initrd.postDeviceCommands = lib.mkAfter ''
    echo "tyo0-swap-migration: start"
    swap_device="/dev/disk/by-partlabel/${swapPartitionLabel}"
    root_device="/dev/disk/by-partlabel/${rootPartitionLabel}"

    if [ -e "$swap_device" ]; then
      exit 0
    fi

    if [ ! -e "$root_device" ]; then
      exit 0
    fi

    root_disk_name="$(lsblk -no PKNAME "$root_device" | head -n1)"
    root_part_name="$(lsblk -no KNAME "$root_device" | head -n1)"
    root_partnum="$(lsblk -no PARTN "$root_device" | head -n1)"
    root_sysfs="/sys/class/block/$root_disk_name/$root_part_name"
    root_start_sectors="$(cat "$root_sysfs/start")"
    root_size_sectors="$(cat "$root_sysfs/size")"
    sector_size="$(cat "/sys/class/block/$root_disk_name/queue/logical_block_size")"
    root_start_bytes=$((root_start_sectors * sector_size))
    root_size_bytes=$((root_size_sectors * sector_size))
    root_end_bytes=$((root_start_bytes + root_size_bytes - 1))
    swap_start_bytes=$((root_end_bytes - ${toString swapPartitionBytes} + 1))

    if [ -z "$root_disk_name" ] || [ -z "$root_partnum" ] || [ "$swap_start_bytes" -le "$root_start_bytes" ]; then
      exit 0
    fi

    root_disk="/dev/$root_disk_name"
    btrfs_mount="/btrfs_tmp"

    mkdir -p "$btrfs_mount"
    if ! mount -t btrfs -o subvolid=5 "$root_device" "$btrfs_mount"; then
      echo "tyo0-swap-migration: root mount failed"
      exit 0
    fi

    free_bytes="$(df -B1 "$btrfs_mount" | awk 'NR==2 { print $4 }')"
    if [ -z "$free_bytes" ] || [ "$free_bytes" -lt $(( ${toString swapPartitionBytes} + 134217728 )) ]; then
      echo "tyo0-swap-migration: insufficient free space, skipping"
      umount "$btrfs_mount"
      exit 0
    fi

    echo "tyo0-swap-migration: shrinking btrfs by 1GiB"
    if ! btrfs filesystem resize -${toString (1024)}m "$btrfs_mount"; then
      echo "tyo0-swap-migration: btrfs shrink failed, skipping"
      umount "$btrfs_mount"
      exit 0
    fi

    umount "$btrfs_mount"

    echo "tyo0-swap-migration: resizing partition and creating swap"
    if ! parted -s "$root_disk" unit B resizepart "$root_partnum" "$((swap_start_bytes - 1))"; then
      echo "tyo0-swap-migration: resizepart failed"
      exit 0
    fi

    if ! parted -s "$root_disk" unit B mkpart ${swapPartitionLabel} linux-swap "$swap_start_bytes" "$root_end_bytes"; then
      echo "tyo0-swap-migration: mkpart failed"
      exit 0
    fi

    partprobe "$root_disk" || true
    udevadm settle || true

    if [ -e "$swap_device" ]; then
      echo "tyo0-swap-migration: formatting swap"
      mkswap -L "${swapPartitionLabel}" "$swap_device"
    fi

    echo "tyo0-swap-migration: done"
  '';
  nix.gc.automatic = lib.mkForce true;
}
