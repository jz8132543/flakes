{ config, pkgs, ... }: 

{
  # BOOT
  boot = {
    cleanTmpDir = true;
    tmpOnTmpfs = false;
    kernelModules = [ "tcp_bbr" ];
    kernel.sysctl."net.ipv4.tcp_congestion_control" = "bbr";
  };
  networking = {
    domain = "dora.im";
    firewall.enable = false;
  };
  zramSwap.enable = true;
  time.timeZone = "Asia/Shanghai";
  system.stateVersion = "22.11";
  services.openssh.enable = true;

  # NIX
  nix = {
    package = pkgs.nixFlakes; # or versioned attributes like nixVersions.nix_2_8
    gc = {
      automatic = true;
      options = "--delete-older-than 5d";
      dates = "Sun 19:00";
    };
    settings = {
      auto-optimise-store = true;
      substituters = [
        "https://nixos-cn.cachix.org"
      ];
      trusted-public-keys = [
        "nixos-cn.cachix.org-1:L0jEaL6w7kwQOPlLoCR3ADx+E3Q8SEFEcB9Jaibl0Xg="
      ];
    };
    extraOptions = ''
      experimental-features = nix-command flakes
      warn-dirty = false
    '';
  };
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.packageOverrides = pkgs: {
    nur = import (builtins.fetchTarball "https://github.com/nix-community/NUR/archive/master.tar.gz") {
      inherit pkgs;
    };
  };

  # PKG
  environment.systemPackages = with pkgs;[
    cachix
    home-manager
    vim
    neovim
    tmux
    restic
    git
  ];
}
