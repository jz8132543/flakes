{ nixosConfig, lib, pkgs, ...  }:

lib.mkIf nixosConfig.environment.graphical.enable {
  home.packages = with pkgs;  [
    bitwarden
    bitwarden-cli
  ];
  home.global-persistence = {
    directories = [
    ];
  };

}
