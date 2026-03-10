{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.desktop;
in
{
  home.packages = with pkgs; [
    qt6Packages.fcitx5-configtool
  ];

  xdg.dataFile."fcitx5/rime" = {
    source = "${pkgs.fcitx5-rime}/share/rime-data";
    recursive = true;
  };

  xdg.configFile."fcitx5/config" = {
    text = ''
      [Behavior]
      # Do not share input state between any windows/apps
      ShareInputState=No
      # Enable application filter for the groups/rules below
      EnableApplicationFilter=True

      [Hotkey]
      EnumerateWithTriggerKeys=True
      [Hotkey/TriggerKeys]
      0=Control+space
      1=Shift_R
      2=Shift_L
      [Hotkey/EnumerateForwardKeys]
      0=Shift_L
      1=Shift_R
    '';
    force = true;
  };

  xdg.configFile."fcitx5/profile" = {
    text = ''
      [Groups/0]
      Name=Default
      Default Layout=us
      DefaultIM=keyboard-us

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

  xdg.configFile."autostart/org.fcitx.Fcitx5.desktop" = lib.mkIf (cfg.environment == "kde") {
    text = ''
      [Desktop Entry]
      Hidden=true
    '';
    force = true;
  };

  systemd.user.services."app-org.fcitx.Fcitx5@autostart" = lib.mkIf (cfg.environment == "kde") {
    Unit.ConditionPathExists = "/run/fcitx5-autostart-disabled";
  };

  home.activation.maskFcitxAutostartUnit = lib.hm.dag.entryAfter [ "writeBoundary" ] (
    lib.optionalString (cfg.environment == "kde") ''
      mkdir -p "${config.xdg.configHome}/systemd/user"
      ln -sfn /dev/null "${config.xdg.configHome}/systemd/user/app-org.fcitx.Fcitx5@autostart.service"
    ''
  );

  # Use NixOS level input method configuration
  home.sessionVariables = lib.mkMerge [
    {
      SDL_IM_MODULE = "fcitx";
      XMODIFIERS = "@im=fcitx";
      XIM = "fcitx";
    }
    (lib.mkIf (cfg.environment == "gnome") {
      # GNOME Wayland uses fcitx5 through the ibus frontend / text-input-v3 path.
      # Keep GTK on the desktop default path instead of forcing fcitx IM module
      # globally, which is explicitly discouraged by upstream docs.
      QT_IM_MODULE = "fcitx";
    })
    (lib.mkIf (cfg.environment == "kde") {
      QT_IM_MODULES = "wayland;fcitx;ibus";
    })
  ];
}
