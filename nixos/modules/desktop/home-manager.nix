{ ... }:
{
  # Importing the desktop profile opts its managed users into desktop settings.
  # Path-based module imports are deduplicated with the existing X11 user entry.
  home-manager.sharedModules = [
    ({ hmModules, ... }: { imports = hmModules.desktop.all; })
  ];
}
