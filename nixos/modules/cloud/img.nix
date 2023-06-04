{
  config,
  pkgs,
  lib,
  modulesPath,
  ...
}:
with pkgs; let
  inherit (config.system.build) toplevel;
  db = closureInfo {rootPaths = [toplevel];};
  tools = lib.makeBinPath (
    with pkgs; [
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
in {
  system.build.image = vmTools.runInLinuxVM (runCommand "${config.system.name}"
    {
      memSize = 4096;
      preVM = ''
        mkdir $out
        diskImage=$out/nixos.img
        ${vmTools.qemu}/bin/qemu-img create -f raw $diskImage $(( $(cat ${db}/total-nar-size) + 2000000000 ))
      '';
    } ''
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
    '');
}
