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
in
lib.mkIf (imFramework == "ibus") {
  xdg.configFile."ibus/rime" = {
    source = pkgs.rime-deploy.override {
      framework = "ibus";
      inherit terminalEnglishApps;
    };
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
