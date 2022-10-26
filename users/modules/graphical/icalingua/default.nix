{ nixosConfig, lib, pkgs, ...  }:

lib.mkIf nixosConfig.environment.graphical.enable {
  home.packages = with pkgs;  [
    nur.repos.linyinfeng.icalingua-plus-plus
  ];
  home.global-persistence = {
    directories = [
      ".config/icalingua"
    ];
  };

}
