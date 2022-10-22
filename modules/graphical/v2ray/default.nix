{ config, lib, pkgs, ...  }:

lib.mkIf config.environment.graphical.enable{
  services = {
    v2ray = {
      enable = true;
      configFile = "/etc/v2ray/config.json";
    };
  };
  environment.global-persistence = {
    directories = [
     "/etc/v2ray"
    ];
  };


}