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

  documentation = {
    nixos.enable = false;
    man.generateCaches = false;
  };
  programs.command-not-found.enable = false;
  programs.nix-index = {
    enable = true;
    package = pkgs.nix-index-with-db;
  };

  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_zen;
  security.rtkit.enable = true;
  services.dbus.implementation = "broker";
  services.bpftune.enable = true;
  services.earlyoom.enable = true;
  boot.kernel.sysctl = {
    "kernel.sysrq" = 1;
  };

  services.journald.extraConfig = ''
    SystemMaxUse=100M
    SystemKeepFree=1G
  '';
}
