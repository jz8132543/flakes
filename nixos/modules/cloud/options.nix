{
  lib,
  ...
}:
{
  options.utils = {
    disk = lib.mkOption {
      type = lib.types.str;
      default = "/dev/vda";
      description = "disko disk";
    };
    btrfsMixed = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Btrfs mixed block groups (-M)";
    };
  };
}
