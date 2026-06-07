{ pkgs, ... }:
{
  home.packages = with pkgs; [
    aria2
    # TODO: fix ariang
    # ariang
  ];
}
