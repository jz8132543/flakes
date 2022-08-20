{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    home-manager
    tmux
    git
    vim
  ];
}
