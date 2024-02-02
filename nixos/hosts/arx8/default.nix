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
  # environment.isCN = true;
  environment.systemPackages = with pkgs; [
    lenovo-legion
    refind
    efibootmgr
  ];
}
