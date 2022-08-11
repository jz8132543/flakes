{ config, pkgs, ... }: 

{
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.packageOverrides = pkgs: {
    nur = import (builtins.fetchTarball "https://github.com/nix-community/NUR/archive/master.tar.gz") {
      inherit pkgs;
    };
  };
  nix = {
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
  };

  environment.systemPackages = with pkgs;[
    cachix
    neovim
    home-manager
    vim
    neovim
    tmux
    restic
    git
    kubernetes-helm
  ];
}
