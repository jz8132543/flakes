{ config, lib, pkgs, ...  }:

lib.mkIf config.environment.graphical.enable{
  services = {
    v2ray = {
      enable = true;
      configFile = "/etc/xray/config.json";
    };
  };
  environment.global-persistence = {
    directories = [
     "/etc/xray"
    ];
  };


}
