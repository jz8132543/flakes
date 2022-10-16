{ config, lib, pkgs, ...  }:

lib.mkIf config.environment.graphical.enable{
  hardware.video.hidpi.enable = true;
}
