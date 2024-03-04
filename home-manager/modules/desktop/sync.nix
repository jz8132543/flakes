{
  config,
  osConfig,
  lib,
  ...
}: {
  services.syncthing = {
    enable = true;
    tray.enable = true;
    extraOptions = [
      # see https://docs.syncthing.net/users/syncthing.html
      "--config=${config.xdg.configHome}/syncthing"
      "--data=${config.xdg.dataHome}/syncthing"
      "--gui-address=0.0.0.0:${toString osConfig.ports.syncthing}"
    ];
  };
  home.global-persistence.directories = [
    ".config/syncthing"
    ".local/share/syncthing"
  ];
  # rime
  home.file.".local/share/syncthing/rime/global".source = "${(lib.lists.last osConfig.i18n.inputMethod.ibus.engines).outPath}/share/rime-data";
  home.file.".local/share/syncthing/rime/user".source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/ibus/rime";
}
