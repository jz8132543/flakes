{
  nixosConfig,
  config,
  lib,
  pkgs,
  ...
}: {
  xdg = {
    enable = true;
    userDirs = {
      enable = true;
      createDirectories = true;
      desktop = "$HOME/.local/XDG/Desktop";
      documents = "$HOME/.local/XDG/Documents";
      download = "$HOME/.local/XDG/Downloads";
      templates = "$HOME/.local/XDG/Templates";
      music = "$HOME/.local/XDG/Music";
      videos = "$HOME/.local/XDG/Videos";
      pictures = "$HOME/.local/XDG/Pictures";
      publicShare = "$HOME/.local/XDG/Public";
    };
    configFile = {
      "sioyek/prefs_user.config".text = ''
      '';
      "go/env".text = ''
        GOPATH=${config.xdg.cacheHome}/go
        GOBIN=${config.xdg.stateHome}/go/bin
        GO111MODULE=on
        GOPROXY=https://goproxy.cn
        GOSUMDB=sum.golang.google.cn
      '';
    };
  };
  home.global-persistence = {
    directories = [
      ".local/XDG"
    ];
  };
}
