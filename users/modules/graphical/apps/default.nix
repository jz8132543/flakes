{ nixosConfig, lib, pkgs, ...  }:

lib.mkIf nixosConfig.environment.graphical.enable {
  home.packages = with pkgs;  [
    go
    mpv

    logseq
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
