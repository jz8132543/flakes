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
  renderAppOptions =
    apps:
    lib.concatMapStrings (app: ''
      "${app}":
        ascii_mode: true
    '') apps;
  rimeDefaultCustom = pkgs.writeText "default.custom.yaml" ''
    patch:
      schema_list:
        - schema: wanxiang
      ascii_composer:
        good_old_caps_lock: true
        switch_key:
          Shift_L: noop
          Shift_R: noop
      app_options:
    ${renderAppOptions terminalEnglishApps}
  '';
  rimeUserData = pkgs.runCommandLocal "ibus-rime-user-data" { } ''
    cp -r ${pkgs.rime-deploy}/share/rime-data $out
    chmod -R u+w $out
    cp ${rimeDefaultCustom} $out/default.custom.yaml
  '';
in
lib.mkIf (imFramework == "ibus") {
  xdg.configFile."ibus/rime" = {
    source = rimeUserData;
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
