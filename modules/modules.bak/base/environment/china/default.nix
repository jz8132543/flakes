{ config, options, lib, pkgs, ... }:

let
  cfg = config.environment.China;
in

with lib;
{
  options.hardware.china = {
    enable = lib.mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to enable graphical environment.
      '';
    };
  };
}
