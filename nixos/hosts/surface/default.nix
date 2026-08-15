{
  nixosModules,
  ...
}:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.desktop.all
    ++ [
      ./hardware-configuration.nix
      ./hardware.nix
      nixosModules.optimize.network-desktop
      nixosModules.optimize.fakehttp
      nixosModules.services.traefik
      nixosModules.optimize.dev
      nixosModules.services.qbittorrent
    ];

  services.tailscale.enable = true;
}
