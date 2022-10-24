{ config, lib, pkgs, ...  }:

lib.mkIf config.hardware.graphical.enable {
  environment.systemPackages = with pkgs; [
    wineWowPackages.staging
    winetricks
  ];

  environment.global-persistence.user.directories = [
    ".wine"
  ];
}
