{
  lib,
  pkgs,
  ...
}:
{
  # disko's current image builder passes an aggregated modules tree as
  # vmTools.kernel. Newer nixpkgs cannot infer a bootable kernel image from
  # that tree, so provide the kernel image name explicitly for all disk images.
  disko.imageBuilder = {
    kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
    pkgs = lib.mkDefault (
      pkgs.extend (
        _final: prev: {
          vmTools = prev.vmTools.override {
            kernelImage = "bzImage";
          };
        }
      )
    );
  };
}
