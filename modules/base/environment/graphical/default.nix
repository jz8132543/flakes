{ config, options, lib, pkgs, ... }:

let
  cfg = config.environment.graphical;
in

with lib;
{
  options.environment.graphical = {
    enable = lib.mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to enable graphical environment.
      '';
    };
    manager = lib.mkOption {
      type = types.str;
      default = "sway";
      description = ''
        The window manager.
      '';
    };
  };
  config.environment.China = mkIf cfg.enable {
    enable = true;
  };
}
