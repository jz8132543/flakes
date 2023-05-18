{
  lib,
  config,
  ...
}: {
  options.utils.disk = lib.mkOption {
    type = lib.types.str;
    default = "/dev/vda";
    description = "disko disk";
  };
}
