{ config, lib, pkgs, ...  }:

lib.mkIf config.environment.graphical.enable{
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
  };

  environment.global-persistence = {
    user.directories = [
      ".steam"
    ];
  };
}
