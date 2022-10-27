{ config, lib, pkgs, ...  }:

lib.mkIf config.environment.graphical.enable{
  virtualisation = {
    kvmgt = {
      enable = true;
      vgpus = {
        i915-GVTg_V5_4.uuid = [ "d577a7cf-2595-44d8-9c08-c67358dcf7ac" ];
      };
    };
  };
}
