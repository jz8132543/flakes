{
  pkgs,
  lib,
  ...
}: {
  time.timeZone = "Asia/Shanghai";

  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  documentation = {
    nixos.enable = false;
    man.generateCaches = false;
  };
  programs.command-not-found.enable = false;
  services.journald.extraConfig = ''
    SystemMaxUse=100M
    SystemKeepFree=1G
  '';
}
