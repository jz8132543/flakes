{
  pkgs,
  config,
  lib,
  ...
}:
let
  # Rime global settings: Wanxiang schema and Shift toggle
  defaultCustomYaml = ''
    patch:
      schema_list:
        - schema: wanxiang
      ascii_composer:
        good_old_caps_lock: true
        switch_key:
          Shift_L: commit_code
          Shift_R: commit_code
      # Rime internal per-app settings
      app_options:
        # Default to English (ASCII) for these apps
        # The key is usually the binary name or WM_CLASS
        kitty:
          ascii_mode: true
        alacritty:
          ascii_mode: true
        foot:
          ascii_mode: true
        neovide:
          ascii_mode: true
  '';

  rimeMergedData = pkgs.runCommand "rime-merged-data" { } ''
    mkdir -p $out
    # Copy base package files
    if [ -d "${pkgs.rime-wanxiang-base}/share/fcitx5/rime" ]; then
      cp -rf ${pkgs.rime-wanxiang-base}/share/fcitx5/rime/* $out/
    fi
    # Copy gram file
    cp -f ${pkgs.rime-wanxiang-gram}/share/fcitx5/rime/wanxiang-lts-zh-hans.gram $out/

    # Safer file generation without indentation issues
    printf "%s" ${lib.escapeShellArg defaultCustomYaml} > $out/default.custom.yaml
    cp -f ${./wanxiang.custom.yaml} $out/wanxiang.custom.yaml
  '';
  # Keep filters empty if we want Rime to handle state instead of killing Rime
  disabledApps = [ ];
in
{
  home.packages = with pkgs; [
    rime-wanxiang-base
    rime-wanxiang-gram
  ];

  home.file.".local/share/fcitx5/rime" = {
    source = rimeMergedData;
    recursive = true;
  };

  xdg.configFile."fcitx5/config" = {
    text = ''
      [Behavior]
      # Do not share input state between any windows/apps
      ShareInputState=No
      # Disable Fcitx5-level app filtering to let Rime handle it
      EnableApplicationFilter=False
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
