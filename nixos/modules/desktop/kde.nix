{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.desktop;
in
lib.mkIf (cfg.environment == "kde") {
  services = {
    xserver.enable = true;
    displayManager = {
      gdm.enable = lib.mkForce false;
      sddm = {
        enable = true;
        wayland.enable = true;
        theme = "where_is_my_sddm_theme";
        extraPackages = [ pkgs.where-is-my-sddm-theme ];
      };
    };
    desktopManager = {
      gnome.enable = lib.mkForce false;
      plasma6.enable = true;
    };
  };

  programs.kdeconnect.enable = true;

  environment.systemPackages =
    (with pkgs.kdePackages; [
      dolphin
      filelight
      gwenview
      kdeconnect-kde
      konsole
      spectacle
    ])
    ++ lib.optionals (cfg.environment == "kde") [
      pkgs.kdePackages.plasma-browser-integration
    ];
}
