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
      ]
      osConfig;
  rimeUserData =
    if osConfig ? system && osConfig.system ? build && osConfig.system.build ? rimeUserData then
      osConfig.system.build.rimeUserData
    else
      pkgs.rime-deploy.override {
        framework = "fcitx5";
        inherit terminalEnglishApps;
      };
in
lib.mkIf (imFramework == "fcitx5") {
  home.packages = with pkgs; [
    qt6Packages.fcitx5-configtool
  ];

  home.global-persistence.directories = [
    {
      directory = ".config/fcitx5";
      mode = "0700";
    }
    {
      directory = ".local/share/fcitx5";
      mode = "0700";
    }
  ];

  xdg.dataFile."fcitx5/rime" = {
    source = rimeUserData + "/share/rime-build";
    recursive = true;
  };

  # Rime writes these at startup; migrate the old store links without losing state.
  home.activation.initializeRimeState = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    rime_dir=${lib.escapeShellArg "${config.xdg.dataHome}/fcitx5/rime"}
    run mkdir -p "$rime_dir"
    for name in installation.yaml user.yaml; do
      state="$rime_dir/$name"
      if [ -L "$state" ] && [[ "$(readlink -f "$state")" == /nix/store/* ]]; then
        run cp --remove-destination "$(readlink -f "$state")" "$state"
        run chmod u+w "$state"
      elif [ ! -e "$state" ] && [ ! -L "$state" ]; then
        run cp ${rimeUserData}/share/rime-data/"$name" "$state"
        run chmod u+w "$state"
      fi
    done
    run mkdir -p "$rime_dir/build"
    for source in ${rimeUserData}/share/rime-data/build/*.yaml; do
      run cp --remove-destination "$source" "$rime_dir/build/$(basename "$source")"
      run chmod u+w "$rime_dir/build/$(basename "$source")"
    done
  '';

  xdg.configFile."fcitx5/config" = {
    text = ''
      [Behavior]
      ActiveByDefault=True
      ShareInputState=All

      [Hotkey]
      EnumerateWithTriggerKeys=True
      [Hotkey/TriggerKeys]
      0=Control+space
      # Shift belongs to Rime's ASCII toggle, not Fcitx's input-method switching.
      [Hotkey/AltTriggerKeys]
      [Hotkey/EnumerateForwardKeys]
    '';
    force = true;
  };

  xdg.configFile."fcitx5/conf/classicui.conf" = {
    text = ''
      Font=Sans 10
      MenuFont=Sans 10
      TrayFont=Sans Bold 10
      EnableFractionalScale=True
    '';
    force = true;
  };

  xdg.configFile."fcitx5/profile" = {
    text = ''
      [Groups/0]
      Name=Default
      Default Layout=us
      DefaultIM=rime

      [Groups/0/Items/0]
      Name=keyboard-us
      Layout=

      [Groups/0/Items/1]
      Name=rime
      Layout=

      # --- 分组 1: 终端专用的纯英文模式 ---
      [Groups/1]
      Name=TerminalOnly
      Default Layout=us
      DefaultIM=keyboard-us

      [Groups/1/Items/0]
      Name=keyboard-us
      Layout=

      # 匹配规则：强制让终端类应用使用 Groups/1 (仅英文)
      [Groups/1/Rules/0]
      Match=wm_class
      String=kitty

      [Groups/1/Rules/4]
      Match=app_id
      String=kitty

      [Groups/1/Rules/1]
      Match=wm_class
      String=Alacritty

      [Groups/1/Rules/5]
      Match=app_id
      String=Alacritty

      [Groups/1/Rules/8]
      Match=wm_class
      String=alacritty

      [Groups/1/Rules/9]
      Match=app_id
      String=alacritty

      [Groups/1/Rules/10]
      Match=wm_class
      String=org.wezfurlong.wezterm

      [Groups/1/Rules/11]
      Match=app_id
      String=org.wezfurlong.wezterm

      [Groups/1/Rules/12]
      Match=app_id
      String=org.gnome.Console

      [Groups/1/Rules/13]
      Match=wm_class
      String=gnome-terminal-server

      [Groups/1/Rules/2]
      Match=wm_class
      String=foot

      [Groups/1/Rules/6]
      Match=app_id
      String=foot

      [Groups/1/Rules/3]
      Match=wm_class
      String=neovide

      [Groups/1/Rules/7]
      Match=app_id
      String=neovide

      [GroupOrder]
      0=Default
      1=TerminalOnly
    '';
    force = true;
  };

  # Use NixOS level input method configuration
  home.sessionVariables = lib.mkMerge [
    {
      SDL_IM_MODULE = "fcitx";
      XMODIFIERS = "@im=fcitx";
      XIM = "fcitx";
    }
    {
      # Native GTK uses the compositor's text-input path; Qt uses the addon.
      # Terminal ASCII behavior is retained by the existing Rime/app policies.
      QT_IM_MODULE = "fcitx";
    }
  ];
}
