{
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    inputs.nix-index-database.nixosModules.nix-index
  ];
  time.timeZone = "Asia/Shanghai";

  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  documentation = {
    nixos.enable = false;
    man.generateCaches = false;
  };
  programs.command-not-found.enable = false;
  programs.nix-index = {
    enable = true;
    package = pkgs.nix-index-with-db;
  };
  services.journald.extraConfig = ''
    SystemMaxUse=100M
    SystemKeepFree=1G
  '';
}
