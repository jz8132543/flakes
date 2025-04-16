# Source: github/oxalica
# We avoid wayland scaling since fractional scaling support is still TODO.
# https://gitlab.freedesktop.org/wayland/wayland-protocols/-/merge_requests/143
# https://blog.lilydjwg.me/2022/2/2/wayfire-migration-4-not-so-high-dpi.216078.html
{
  lib,
  config,
  ...
}:
let
  inherit (lib)
    mkOption
    mkDefault
    mkIf
    types
    ;
  cfg = config.wayland.dpi;
  default = 96;
in
{
  options = {
    wayland.dpi = mkOption {
      type = types.ints.positive;
      inherit default;
      example = 120;
      description = ''
        Force overriding DPI for programs to avoid bitmap scaling in compositor.
      '';
    };
  };

  config = mkIf (cfg != default) {
    dconf.enable = mkDefault true;
    # dconf.settings."org/gnome/desktop/interface".text-scaling-factor = cfg * 1.0 / default;
    dconf.settings."org/gnome/desktop/interface".scaling-factor = cfg * 1.0 / default;
    xresources.properties."Xft.dpi" = cfg;
    home.sessionVariables = {
      GDK_BACKEND = "wayland";
      CLUTTER_BACKEND = "wayland";
      QT_QPA_PLATFORM = "wayland-egl";
      # QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      # MOZ_ENABLE_WAYLAND = "1";
      # MOZ_USE_XINPUT2 = "1";
      # QT_WAYLAND_FORCE_DPI = cfg;
      SDL_VIDEODRIVER = "wayland";
      # QT_STYLE_OVERRIDE = lib.mkDefault "gtk";
      _JAVA_AWT_WM_NONREPARENTING = "1";
      # XCURSOR_SIZE = 36 * cfg / default;
      # QT_SCALE_FACTOR = cfg * 1.0 / default;
    };
  };
}
