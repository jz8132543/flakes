{nixosModules, ...}: {
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.desktop.all
    ++ [
      ./hardware-configuration.nix
    ];

  microsoft-surface = {
    kernelVersion = "6.1.18";
    surface-control.enable = true;
    # ipts.enable = true;
  };
}
