{
  pkgs,
  lib,
  config,
  osConfig,
  ...
}:
let
  archived = import ../../../archive/desktop/gnome/home-manager/modules/desktop/gnome.nix.bak {
    inherit
      pkgs
      lib
      config
      osConfig
      ;
  };
  # Keep GNOME's native IBus unit instead of restoring the archived Plasma panel bridge.
  legacy = archived // {
    systemd = archived.systemd // {
      user = archived.systemd.user // {
        services = builtins.removeAttrs archived.systemd.user.services [
          "org.freedesktop.IBus.session.GNOME"
        ];
      };
    };
  };
in
{
  config = lib.mkIf osConfig.desktop.gnome.enable (
    lib.mkMerge [
      legacy
      (import ../../../archive/desktop/gnome/home-manager/modules/desktop/kitty.nix.bak)
    ]
  );
}
