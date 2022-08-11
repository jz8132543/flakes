{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs;[
    kubernetes-helm
  ];
}
