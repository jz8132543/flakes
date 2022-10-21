{ config, lib, pkgs, ...  }:

lib.mkIf config.environment.graphical.enable {
  environment.systemPackages = with pkgs; [
    wineWowPackages.staging
    winetricks
  ];

  environment.global-persistence.user.directories = [
    ".wine"
  ];
}
