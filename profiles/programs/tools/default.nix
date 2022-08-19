{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    tmux
    git
    vim
  ];
}
