{ lib, config, ... }:

{
  config.environment.global-persistence.enable = true;
  options.utils.disk = lib.mkOption {
    type = lib.types.str;
    default = "/dev/vda";
    description = "disko disk";
  };
}
