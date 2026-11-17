{ lib, ... }:
{
  options.desktop = {
    mactahoe = {
      startupPackage = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        internal = true;
        description = "Declared, licensed Plymouth and GRUB assets, also exposed for checks.";
      };
    };
  };
}
