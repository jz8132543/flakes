{
  pkgs,
  config,
  lib,
  ...
}:
{
  imports = [
    # network-auto-tune.nix 已将功能并入 nixos/modules/optimize/minimal.nix （写死静态配置）
    # ./network-auto-tune.nix
  ];
  time.timeZone = "Asia/Shanghai";
  time.hardwareClockInLocalTime = true;
  networking.domain = "dora.im";

  documentation = {
    nixos.enable = false;
    man.cache.enable = false;
  };
  programs.nix-index = {
    enable = pkgs ? nix-index-with-db;
    package = pkgs.nix-index-with-db;
  };
  programs.command-not-found.enable = false;

  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
  security.rtkit.enable = true;
  services.dbus.implementation = "broker";
  services.bpftune.enable = false;
  services.irqbalance.enable = true;
  boot.kernel.sysctl = {
    "kernel.sysrq" = 1;
  };
  boot.initrd.systemd.emergencyAccess = true;
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

  sops.secrets."nix/github-token" = {
    mode = "0440";
    group = config.users.groups.users.name;
  };
  xdg.portal.config.common.default = "*";
  nix.extraOptions = ''
    !include ${config.sops.secrets."nix/github-token".path}
    download-buffer-size = 268435456
  '';

  programs.fish.enable = true;
  programs.zsh.enable = true;
}
