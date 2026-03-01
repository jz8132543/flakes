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
          Shift_L: noop
          Shift_R: noop
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

      [Hotkey]
      # TriggerKeys=Shift_L;Shift_R
      # NextIM 也要留着，保证在组内循环
      # NextIM=Shift_L;Shift_R
      # 必须开启，否则 Shift 无法作为单按键生效
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
    echo 1
    # 运行 librime 提供的命令行部署工具
    # ~/.local/share/fcitx5/rime 是 Fcitx5-Rime 默认的用户数据目录
    ${pkgs.librime}/bin/rime_deployer --build ~/.local/share/fcitx5/rime
    echo 2
    # 可选：如果部署后 fcitx5 正在运行，让其重新加载
    ${pkgs.fcitx5}/bin/fcitx5-remote -r || true
    echo 3
  '';
}
