{ pkgs, ... }:
{
  # all fonts are linked to /nix/var/nix/profiles/system/sw/share/X11/fonts
  fonts = {
    packages = with pkgs; [

    ];
  };
}
