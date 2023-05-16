{ pkgs, ... }:
{
  home.persistence."/nix/persist/home/tippy" = {
    directories = [
      # ".config/dconf"
      ".config/goa-1.0" # gnome accounts
      ".config/gnome-boxes"
      ".local/share/keyrings"
      ".local/share/applications"
      ".local/share/Trash"
      ".local/share/webkitgtk" # gnome accounts
      ".local/share/backgrounds"
      ".local/share/gnome-boxes"
      ".local/share/icc" # user icc files
      ".cache/tracker3"
      ".cache/thumbnails"
    ];
    files = [
      ".face"
      ".config/monitors.xml"
    ];
  };
}
