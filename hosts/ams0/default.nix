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

  nix = {
    package = pkgs.nixFlakes; # or versioned attributes like nixVersions.nix_2_8
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };
  nixpkgs.config.allowUnfree = true;

  boot = {
    cleanTmpDir = true;
    tmpOnTmpfs = false;
    kernelPackages = pkgs.linuxPackages_xanmod_latest;
    kernelModules = [ "tcp_bbr" ];
    kernel.sysctl."net.ipv4.tcp_congestion_control" = "bbr";
  };
  zramSwap.enable = true;
  networking = {
    hostName = "ams0";
    domain = "dora.im";
    firewall.enable = false;
  };
  time.timeZone = "Asia/Shanghai";
  system.stateVersion = "22.11";
  services.openssh.enable = true;
}
