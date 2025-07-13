{
  pkgs,
  lib,
  ...
}:
{
  time.timeZone = "Asia/Shanghai";

  documentation = {
    nixos.enable = false;
    man.generateCaches = false;
  };
  programs.nix-index = {
    enable = pkgs ? nix-index-with-db;
    package = pkgs.nix-index-with-db;
  };
  programs.command-not-found.enable = false;

  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_zen;
  security.rtkit.enable = true;
  services.dbus.implementation = "broker";
  services.bpftune.enable = true;
  services.earlyoom.enable = true;
  boot.kernel.sysctl = {
    "kernel.sysrq" = 1;
  };
  systemd.oomd = {
    enable = true;
    enableSystemSlice = true;
    enableRootSlice = true;
    enableUserSlices = true;
  };

  services.journald.extraConfig = ''
    SystemMaxUse=100M
    SystemKeepFree=1G
  '';
}
