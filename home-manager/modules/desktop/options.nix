{
  lib,
  osConfig ? { },
  ...
}:
let
  defaultEnvironment = lib.attrByPath [ "desktop" "environment" ] "kde" osConfig;
in
{
  options.desktop.environment = lib.mkOption {
    type = lib.types.enum [
      "gnome"
      "kde"
    ];
    default = defaultEnvironment;
    description = "Desktop environment profile for Home Manager customizations.";
  };
}
