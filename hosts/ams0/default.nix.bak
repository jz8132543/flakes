{ config, pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./pkgs.nix
    ../../users
    ../../modules/sops
    ../../modules/acme
    ../../modules/traefik
    ../../modules/k3s
  ];

  networking.hostName = "ams0";

}
