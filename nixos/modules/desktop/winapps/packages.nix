{
  pkgs,
  inputs,
  config,
  lib,
  ...
}:

let
  cfg = config.desktop.winapps;
in
{
  config = lib.mkIf (cfg.kvm.enable || cfg.docker.enable) {
    environment.systemPackages =
      with pkgs;
      [
        # Virtual Machine Manager GUI
        virt-manager
        # FreeRDP is required by WinApps to connect to the VM seamlessly
        freerdp
        # WinApps package from the community flake
        inputs.winapps.packages.${pkgs.system}.winapps
        inputs.winapps.packages.${pkgs.system}.winapps-launcher
      ]
      ++ lib.optionals cfg.kvm.enable [
        # Dependencies for KVM dynamic disk discovery script
        os-prober
        util-linux
      ];
  };
}
