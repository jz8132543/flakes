{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.umbriel.nixosModules.default ];

  config = lib.mkIf config.desktop.umbriel.enable {
    desktop.inputMethod.framework = lib.mkDefault "fcitx5";
    i18n.inputMethod.fcitx5.waylandFrontend = lib.mkDefault true;
    desktop.noctalia = {
      enable = lib.mkDefault true;
      sessionTarget = lib.mkDefault "umbriel-session.target";
    };
    programs.umbriel.enable = true;
    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      config.umbriel = {
        default = [
          "umbriel"
          "gtk"
        ];
        "org.freedesktop.impl.portal.ScreenCast" = [ "umbriel" ];
        "org.freedesktop.impl.portal.Screenshot" = [ "umbriel" ];
        "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
        "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
      };
    };
    environment.systemPackages = [ pkgs.brightnessctl ];
    services.udev.packages = [ pkgs.brightnessctl ];
    programs.dconf.enable = true;
    nix.settings = {
      extra-substituters = [
        "https://umbriel.cachix.org"
        "https://noctalia.cachix.org"
      ];
      extra-trusted-public-keys = [
        "umbriel.cachix.org-1:JfNq/2yg2S6D6z4Z2dVSZrZlDPQTKtexB6GAVLD98nw="
        "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      ];
    };
  };
}
