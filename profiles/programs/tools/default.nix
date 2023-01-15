{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    home-manager
    tmux
    git
    vim
    screen
    deploy-rs
    wget
    gptfdisk
    unzip
  ];
}
