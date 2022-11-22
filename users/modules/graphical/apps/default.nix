{ nixosConfig, lib, pkgs, ...  }:

lib.mkIf nixosConfig.environment.graphical.enable {
  home.packages = with pkgs;  [
    go
    mpv

    logseq
    wpsoffice
    nur.repos.pokon548.v2raya-unstable
    nur.repos.xddxdd.baidupcs-go
    nur.repos.xddxdd.bilibili
    nur.repos.xddxdd.wechat-uos
  ];
  home.global-persistence = {
    directories = [
      ".logseq"
      ".config/Logseq"
    ];
  };

}
