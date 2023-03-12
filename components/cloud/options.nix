{ lib, ... }:

{
  options.utils.disk = lib.mkOption {
    type = lib.types.string;
    default = "/dev/vda";
    description = "disko disk";
  };
}
