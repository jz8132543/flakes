{ config, pkgs, lib, modulesPath, ... }:
with pkgs;
let
  inherit (config.system.build) toplevel;
  db = closureInfo { rootPaths = [ toplevel ]; };
  devPath = "/dev/disk/by-partlabel/NIXOS";
in
{
  system.build.image = vmTools.runInLinuxVM (runCommand "image"
    {
      memSize = 4096;
      preVM = ''
        mkdir $out
        diskImage=$out/nixos.img
        ${vmTools.qemu}/bin/qemu-img create -f raw $diskImage $(( $(cat ${db}/total-nar-size) + 2000000000 ))
      '';
      nativeBuildInputs = [ gptfdisk btrfs-progs mount util-linux nixUnstable config.system.build.nixos-install dosfstools ];
    } ''
    sgdisk -Z -n 1:0:+1M -n 2:0:+200M -n 3:0:0 -t 1:ef02 -t 2:EF00 -c 1:BOOT -c 2:EFI -c 3:NIXOS /dev/vda
    mknod /dev/btrfs-control c 10 234
    mkfs.vfat /dev/vda1
    mkfs.vfat /dev/vda2
    mkfs.btrfs /dev/vda3
    # This is needed for systemd-boot to find ESP, and udev is not available here to create this
    # mkdir -p /dev/block
    # ln -s /dev/vda2 /dev/block/254:2
    mkdir /fsroot && mount /dev/vda3 /fsroot
    btrfs subvol create /fsroot/@nix
    btrfs subvol create /fsroot/@persist
    btrfs subvol create /fsroot/@swap
    btrfs subvol create /fsroot/@ROOT
    btrfs subvol create /fsroot/@boot
    mkdir -p /mnt/boot
    mount -o subvol=@ROOT,compress-force=zstd,space_cache=v2 /dev/vda3 /mnt
    mount -o subvol=@boot,compress-force=zstd,space_cache=v2 /dev/vda3 /boot
    mkdir -p /mnt/{boot/efi,nix,persist}
    mount -o subvol=@nix,compress-force=zstd,space_cache=v2 /dev/vda3 /mnt/nix
    mount -o subvol=@persist,compress-force=zstd,space_cache=v2 /dev/vda3 /mnt/persist
    mount /dev/vda2 /mnt/boot/efi
    export NIX_STATE_DIR=$TMPDIR/state
    nix-store --load-db < ${db}/registration
    nixos-install --root /mnt --system ${toplevel} --no-channel-copy --no-root-passwd --substituters ""
  '');
}
