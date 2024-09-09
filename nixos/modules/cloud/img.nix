{
  config,
  pkgs,
  lib,
  ...
}:
with pkgs;
let
  inherit (config.system.build) toplevel;
  db = closureInfo { rootPaths = [ toplevel ]; };
  tools = lib.makeBinPath (
    with pkgs;
    [
      config.system.build.nixos-enter
      config.system.build.nixos-install
      dosfstools
      e2fsprogs
      gptfdisk
      nixUnstable
      parted
      util-linux
      btrfs-progs
    ]
  );
in
{
  system.build.image = vmTools.runInLinuxVM (
    runCommand "${config.system.name}"
      {
        memSize = 4096;
        preVM = ''
          mkdir $out
          diskImage=$out/nixos.img
          ${vmTools.qemu}/bin/qemu-img create -f raw $diskImage $(( $(cat ${db}/total-nar-size) + 2000000000 ))
        '';
      }
      ''
        export PATH=${tools}:$PATH
        set -x
        # Run disko-create
        ${config.system.build.formatScript}
        # Run disko-mount
        ${config.system.build.mountScript}
        # Install NixOS
        export NIX_STATE_DIR=$TMPDIR/state
        nix-store --load-db < ${db}/registration
        nixos-install --root /mnt --system ${toplevel} --no-channel-copy --no-root-passwd --substituters ""
      ''
  );
  # systemd.services = {
  #   "resize-part" = {
  #     wantedBy = ["multi-user.target"];
  #     serviceConfig.Type = "oneshot";
  #     script = ''
  #       udevadm trigger
  #       id=`udevadm info --query all --name=/dev/disk/by-partlabel/NIXOS | sed -n 's/R: //p'`
  #       disk=`${pkgs.util-linux}/bin/lsblk -no pkname /dev/disk/by-partlabel/NIXOS`
  #       ${pkgs.gptfdisk}/bin/sgdisk -e -d ''${id} -n ''${id}:0:0 -c ''${id}:NIXOS -p /dev/''${disk}
  #       ${pkgs.util-linux}/bin/partx -u /dev/''${disk}
  #       ${pkgs.btrfs-progs}/bin/btrfs filesystem resize max /nix
  #     '';
  #   };
  # };
}
