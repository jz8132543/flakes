{
  config,
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
        "konsole"
        "org.kde.konsole"
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
  dconf.settings = {
    # IBus schema IDs use org.freedesktop.ibus, but their paths use /desktop/ibus/.
    "desktop/ibus/panel" = {
      lookup-table-orientation = 0;
      use-custom-font = true;
      custom-font = "LXGW WenKai GB 26";
    };
    "desktop/ibus/general" = {
      embed-preedit-text = false;
      use-global-engine = true;
      preload-engines = [ "rime" ];
    };
  };

  xdg.configFile."ibus/rime" = {
    source = rimeUserData + "/share/rime-build";
    recursive = true;
  };

  # Rime updates these files at runtime; never replace existing learned state.
  home.activation.initializeRimeState = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    rime_dir=${lib.escapeShellArg "${config.xdg.configHome}/ibus/rime"}
    run mkdir -p "$rime_dir"
    for name in installation.yaml user.yaml; do
      if [ ! -e "$rime_dir/$name" ] && [ ! -L "$rime_dir/$name" ]; then
        run cp ${rimeUserData}/share/rime-data/"$name" "$rime_dir/$name"
        run chmod u+w "$rime_dir/$name"
      fi
    done
    run mkdir -p "$rime_dir/build"
    for source in ${rimeUserData}/share/rime-data/build/*.yaml; do
      run cp --remove-destination "$source" "$rime_dir/build/$(basename "$source")"
      run chmod u+w "$rime_dir/build/$(basename "$source")"
    done
  '';

  home.sessionVariables = {
    GTK_IM_MODULE = "ibus";
    QT_IM_MODULE = "ibus";
    SDL_IM_MODULE = "ibus";
    XMODIFIERS = "@im=ibus";
    XIM = "ibus";
  };

  home.global-persistence.directories = [
    ".config/ibus/rime"
  ];
}
