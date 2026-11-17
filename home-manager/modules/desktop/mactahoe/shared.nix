{
  config,
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
let
  theme = pkgs.mactahoe;
  plasmaEnabled = lib.attrByPath [ "services" "desktopManager" "plasma6" "enable" ] false osConfig;
  themes = {
    MacTahoe-Light-solid = theme.gtk;
    MacTahoe-Dark-solid = theme.gtk;
    MacTahoe-Visual-Light = theme.gtkVisual;
    MacTahoe-Visual-Dark = theme.gtkVisual;
  };
in
{
  home.packages = [
    theme.gtk
    theme.gtkVisual
    theme.icons
    theme.cursors
    theme.wallpaper
  ];
  home.file = lib.mapAttrs' (
    name: package:
    lib.nameValuePair ".themes/${name}" {
      source = "${package}/share/themes/${name}";
    }
  ) themes;
  xdg.dataFile =
    (lib.mapAttrs' (
      name: package:
      lib.nameValuePair "themes/${name}" {
        source = "${package}/share/themes/${name}";
      }
    ) themes)
    // (lib.genAttrs [ "MacTahoe" "MacTahoe-light" "MacTahoe-dark" ] (name: {
      target = "icons/${name}";
      source = "${theme.icons}/share/icons/${name}";
    }))
    // (lib.genAttrs [ "icons/MacTahoe-cursors" "icons/MacTahoe-dark-cursors" ] (name: {
      source = "${theme.cursors}/share/${name}";
    }));
  qt = {
    enable = true;
    # Desktop-local platform integration; never force the KDE plugin in GNOME.
    platformTheme = if plasmaEnabled then null else { name = "gtk3"; };
  };
  home.global-persistence.directories = [
    {
      directory = lib.removePrefix "${config.home.homeDirectory}/" "${config.xdg.stateHome}/mactahoe";
      mode = "0700";
    }
  ];
}
