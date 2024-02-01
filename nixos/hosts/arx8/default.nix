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
      nixosModules.networking.nix-binary-cache-mirror
    ];
  environment.systemPackages = with pkgs; [
    lenovo-legion
    refind
    efibootmgr
  ];
}
