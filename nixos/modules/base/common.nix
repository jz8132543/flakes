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

  services.journald.settings.Journal = {
    SystemMaxUse = "100M";
    SystemKeepFree = "1G";
  };

  sops.secrets."github-token" = {
    mode = "0440";
    group = config.users.groups.users.name;
  };
  xdg.portal.config.common.default = "*";

  # Use sops templates to generate the nix config file with the raw token
  sops.templates."nix-access-tokens.conf" = {
    content = "access-tokens = github.com=${config.sops.placeholder."github-token"}";
    mode = "0440";
    group = config.users.groups.users.name;
  };

  nix.extraOptions = ''
    !include ${config.sops.templates."nix-access-tokens.conf".path}
  '';

  programs.fish.enable = true;
  programs.zsh.enable = true;

  # Read the raw GitHub token and set it as an environment variable
  environment.shellInit = ''
    if [ -r ${config.sops.secrets."github-token".path} ]; then
      export GITHUB_TOKEN=$(cat ${config.sops.secrets."github-token".path} | tr -d '\n')
    fi
  '';

  programs.fish.interactiveShellInit = ''
    if test -r ${config.sops.secrets."github-token".path}
      set -gx GITHUB_TOKEN (cat ${config.sops.secrets."github-token".path} | tr -d '\n')
    end
  '';
}
