{ config, pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./pkgs.nix
    ../../users
    ../../modules/sops
    ../../modules/v2ray
    ../../modules/acme
    ../../modules/traefik
    ../../modules/k3s
  ];

  networking.hostName = "tyo0";

}
