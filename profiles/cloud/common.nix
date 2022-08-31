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
      memSize = 512;
      preVM = ''
        mkdir $out
        diskImage=$out/nixos.img
        ${vmTools.qemu}/bin/qemu-img create -f raw $diskImage $(( $(cat ${db}/total-nar-size) + 2000000000 ))
      '';
      nativeBuildInputs = [ gptfdisk btrfs-progs mount util-linux nixUnstable config.system.build.nixos-install dosfstools ];
    } ''
    sgdisk -Z -n 1:0:+110M -n 2:0:0 -t 1:ef02 -c 1:BOOT -c 2:NIXOS /dev/vda
    mknod /dev/btrfs-control c 10 234
    mkfs.vfat /dev/vda1
    mkfs.btrfs /dev/vda2
    mkdir /fsroot && mount /dev/vda2 /fsroot
    btrfs subvol create /fsroot/@tmp
    btrfs subvol create /fsroot/@nix
    btrfs subvol create /fsroot/@persist
    btrfs subvol create /fsroot/@swap
    mkdir -p /mnt/{boot,nix,persist}
    mount /dev/vda1 /mnt/boot
    mount -o subvol=@nix,compress-force=zstd,space_cache=v2 /dev/vda2 /mnt/nix
    mount -o subvol=@persist,compress-force=zstd,space_cache=v2 /dev/vda2 /mnt/persist
    export NIX_STATE_DIR=$TMPDIR/state
    nix-store --load-db < ${db}/registration
    nixos-install --root /mnt --system ${toplevel} --no-channel-copy --no-root-passwd --substituters ""
  '');
}
