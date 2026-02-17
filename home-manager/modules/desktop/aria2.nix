{ pkgs, ... }:
{
  home.packages = with pkgs; [
    aria2
    ariang
  ];
}
