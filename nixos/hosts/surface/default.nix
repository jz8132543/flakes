{
  self,
  nixosModules,
  ...
}: {
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.desktop.all
    ++ [
      ./hardware-configuration.nix
    ];

  # microsoft-surface.ipts.enable = true;
  microsoft-surface.kernelVersion = "6.1.18";
}
