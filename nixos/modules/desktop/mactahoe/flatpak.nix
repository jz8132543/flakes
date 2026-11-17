{ ... }:
{
  # Follow portal color preference. GTK4's managed CSS leaf links directly into
  # the Store, so Flatpak need not see the private appearance state directory.
  services.flatpak.overrides.global.Context.filesystems = [
    "/nix/store:ro"
    "~/.local/share/fonts:ro"
    "~/.local/share/icons:ro"
    "~/.local/share/themes:ro"
    "~/.themes:ro"
    "xdg-config/gtk-3.0:ro"
    "xdg-config/gtk-4.0:ro"
    "xdg-data/themes:ro"
    "xdg-data/icons:ro"
  ];
}
