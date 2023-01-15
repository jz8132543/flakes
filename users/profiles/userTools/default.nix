{ config, pkgs, ... }:

{
  programs.home-manager = {
    enable = true;
  };
  # Allow unfree
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = (pkg: true);
  home.packages = with pkgs; [
    cachix
    thefuck
    bottom
    exa
    bat
    fzf
    fd
    age
    pinentry
    sequoia # gnupg
    sops
    nixfmt
    ripgrep
    duf
    yubikey-manager
    realvnc-vnc-viewer
    podman-compose
  ];
}
