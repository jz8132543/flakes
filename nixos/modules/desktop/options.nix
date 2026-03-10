{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.desktop;
in
{
  options.desktop.environment = lib.mkOption {
    type = lib.types.enum [
      "gnome"
      "kde"
    ];
    default = "gnome";
    description = "Desktop session to preselect at login and tailor user settings for.";
  };

  config.services.displayManager.defaultSession = lib.mkDefault (
    if cfg.environment == "kde" then "plasma" else "gnome"
  );

  config.programs.ssh.askPassword = lib.mkForce (
    if cfg.environment == "kde" then
      "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass"
    else
      "${pkgs.seahorse}/libexec/seahorse/ssh-askpass"
  );
}
