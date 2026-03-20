{ ... }:
{
  services.envfs.enable = true;
  environment.variables.ENVFS_RESOLVE_ALWAYS = "1";
  fileSystems."/usr/bin".options = [
    "x-systemd.requires=modprobe@fuse.service"
    "x-systemd.after=modprobe@fuse.service"
  ];
  # TODO upstream
  # /bin will be canonicalized to /usr/bin
  # Jun 09 02:46:50 parrot systemd-fstab-generator[472]: Found entry what=none where=/usr/bin type=envfs makefs=no growfs=no pcrfs=no noauto=no nofail=yes
  # Jun 09 02:46:50 parrot systemd-fstab-generator[472]: Canonicalized where=/bin to /usr/bin
  # Jun 09 02:46:50 parrot systemd-fstab-generator[472]: Found entry what=/usr/bin where=/usr/bin type=none makefs=no growfs=no pcrfs=no noauto=no nofail=yes
  # Jun 09 02:46:50 parrot systemd-fstab-generator[472]: Failed to create unit file '/run/systemd/generator/usr-bin.mount', as it already exists. Duplicate entry in '/etc/fstab'?
  fileSystems."/bin".enable = false;

  # envfs already provides the initrd tmpfiles entries that stage1 needs for
  # `/sysroot/bin` and `/sysroot/usr/bin`. Duplicating them here can make the
  # initrd tmpfiles setup fail with conflicting rules.
}
