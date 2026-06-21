{
  pkgs,
  lib,
  osConfig ? { },
  ...
}:
let
  imFramework = lib.attrByPath [ "desktop" "inputMethod" "framework" ] "ibus" osConfig;
  terminalEnglishApps =
    lib.attrByPath
      [ "desktop" "inputMethod" "terminalEnglishApps" ]
      [
        "kitty"
        "Alacritty"
        "alacritty"
        "foot"
        "neovide"
        "org.wezfurlong.wezterm"
        "org.gnome.Console"
        "gnome-terminal-server"
        "com.raggesilver.BlackBox"
      ]
      osConfig;
  rimeUserData =
    if osConfig ? system && osConfig.system ? build && osConfig.system.build ? rimeUserData then
      osConfig.system.build.rimeUserData
    else
      pkgs.rime-deploy.override {
        framework = "ibus";
        inherit terminalEnglishApps;
      };
in
lib.mkIf (imFramework == "ibus") {
  xdg.configFile."ibus/rime" = {
    source = rimeUserData + "/share/rime-build";
    recursive = true;
  };

  home.sessionVariables = {
    GTK_IM_MODULE = "ibus";
    QT_IM_MODULE = "ibus";
    SDL_IM_MODULE = "ibus";
    XMODIFIERS = "@im=ibus";
    XIM = "ibus";
  };
}
