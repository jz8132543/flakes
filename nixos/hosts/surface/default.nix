{
  nixosModules,
  pkgs,
  ...
}: {
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.desktop.all
    ++ [
      ./hardware-configuration.nix
    ];

  microsoft-surface = {
    # kernelVersion = "6.4.12";
    surface-control.enable = true;
    # ipts.enable = true;
  };

  environment.systemPackages = with pkgs; [
    refind
    efibootmgr
  ];
}
