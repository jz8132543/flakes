{
  config,
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
let
  migrate = pkgs.writeShellApplication {
    name = "mactahoe-migrate";
    text = ''
      exec ${pkgs.python3}/bin/python3 -B ${./migration.py} \
        --home ${lib.escapeShellArg config.home.homeDirectory} \
        --config-home ${lib.escapeShellArg config.xdg.configHome} \
        --data-home ${lib.escapeShellArg config.xdg.dataHome} \
        --state-home ${lib.escapeShellArg config.xdg.stateHome} \
        --dconf ${pkgs.dconf}/bin/dconf "$@"
    '';
  };
in
{
  config = lib.mkIf (lib.attrByPath [ "desktop" "gnome" "enable" ] false osConfig) {
    # Retain the audit CLI for restored GNOME setups; activation never cleans user data.
    home.packages = [ migrate ];
  };
}
