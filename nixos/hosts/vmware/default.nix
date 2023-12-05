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

  environment.systemPackages = with pkgs; [
    refind
    efibootmgr
  ];
}
