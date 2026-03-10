{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.desktop;
in
{
  services.desktopManager.plasma6.enable = true;

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
