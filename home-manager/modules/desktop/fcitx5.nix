{
  pkgs,
  config,
  lib,
  ...
}:
{
  home.packages = with pkgs; [
    rime-deploy
  ];

  home.file.".local/share/fcitx5/rime" = {
    source = "${pkgs.rime-deploy}/share/rime-data";
    recursive = true;
    onChange = "${pkgs.fcitx5}/bin/fcitx5-remote -r || true";
  };

  xdg.configFile."fcitx5/config" = {
    text = ''
      [Behavior]
      # Do not share input state between any windows/apps
      ShareInputState=No
      # Disable Fcitx5-level app filtering to let Rime handle it
      EnableApplicationFilter=False

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
    '';
    force = true;
  };

  # Use NixOS level input method configuration
  # These session variables are typically set by the NixOS module when fcitx5 is enabled.
  home.sessionVariables = {
    GTK_IM_MODULE = "fcitx";
    QT_IM_MODULE = "fcitx";
    XMODIFIERS = "@im=fcitx";
    XIM = "fcitx";
  };

  home.activation.removeExistingFcitx5Profile = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    # Remove existing fcitx5 and rime configs/data to prevent conflicts
    # This runs before symlinking to ensure a clean state
    rm --recursive --force \
      "${config.xdg.configHome}/fcitx5/profile" \
      "${config.xdg.configHome}/fcitx5/config" \
      "${config.xdg.configHome}/fcitx5/conf" \
      "${config.xdg.configHome}/fcitx5/rime" \
      "${config.xdg.dataHome}/fcitx5/rime" \
      "${config.home.homeDirectory}/.config/fcitx" \
      "${config.home.homeDirectory}/.config/fcitx5" \
      "${config.home.homeDirectory}/.config/rime" \
      "${config.home.homeDirectory}/.local/share/fcitx5"
  '';
}

