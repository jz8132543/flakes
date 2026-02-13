{
  nixosModules,
  lib,
  ...
}:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.services.media.all
    ++ [
      ./hardware-configuration.nix
      ./_steam
      nixosModules.services.ddns
      nixosModules.services.traefik
      # nixosModules.services.postgres
      nixosModules.services.derp
      nixosModules.services.homepage-machine
      nixosModules.desktop.mihomo

      # (import nixosModules.services.matrix { PG = "127.0.0.1"; })
    ];
  # services.qemuGuest.enable = true;

  environment.seedbox.enable = false;

  # Enable NVIDIA HWA for Jellyfin and containers
  systemd.services.jellyfin-disable-transcoding.enable = false;
  users.users.jellyfin.extraGroups = [
    "video"
    "render"
  ];

  environment.isNAT = true;
  environment.isCN = true;

  # Prevent laptop from sleeping on lid close

  ports.derp-stun = lib.mkForce 3440;
  environment.altHTTPS = 8443;

  nix.settings.substituters = lib.mkForce [ "https://mirrors.ustc.edu.cn/nix-channels/store" ];
}
