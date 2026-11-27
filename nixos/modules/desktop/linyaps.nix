{ pkgs, ... }:
{
  services.linyaps.enable = true;
  environment.systemPackages = [ pkgs.linglong-store ];
  xdg.icons.enable = true;
  xdg.sounds.enable = true;
  # Linyaps applications use XDG portals for desktop integration.
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  xdg.portal.config.common.default = "*";
}
