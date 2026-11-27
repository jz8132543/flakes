{ config, lib, ... }:
let
  cfg = config.environment.desktop;
in
{
  options.environment.desktop = {
    dpi = lib.mkOption {
      type = lib.types.ints.positive;
      default = 96;
      description = "Logical desktop DPI used by X11 and legacy desktop applications.";
    };
  };

  # Importing the desktop profile opts its managed users into desktop settings.
  # Path-based module imports are deduplicated with the existing X11 user entry.
  config = {
    environment.variables.WPS_QT_FONT_DPI = toString cfg.dpi;
    home-manager.users.tippy.wayland.dpi = cfg.dpi;
    home-manager.sharedModules = [
      ({ hmModules, ... }: { imports = hmModules.desktop.all; })
    ];
  };
}
