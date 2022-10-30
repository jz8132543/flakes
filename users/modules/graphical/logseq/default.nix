{ nixosConfig, lib, pkgs, ...  }:

lib.mkIf nixosConfig.environment.graphical.enable {
  home.packages = with pkgs; [
    logseq
  ];
  home.global-persistence = {
    directories = [
      ".logseq"
      ".config/Logseq"
    ];
  };
}
