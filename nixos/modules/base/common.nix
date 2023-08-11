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

  services.bpftune.enable = true;

  documentation = {
    nixos.enable = false;
    man.generateCaches = false;
  };
  programs.command-not-found.enable = false;
  programs.nix-index.enable = true;
  programs.nix-index-database.comma.enable = true;
  services.journald.extraConfig = ''
    SystemMaxUse=100M
    SystemKeepFree=1G
  '';
}
