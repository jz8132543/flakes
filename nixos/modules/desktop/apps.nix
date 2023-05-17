{ config, pkgs, ... }:

{
  programs = {
    clash-verge = {
      enable = true;
      autoStart = true;
      tunMode = true;
    };
  };
}


