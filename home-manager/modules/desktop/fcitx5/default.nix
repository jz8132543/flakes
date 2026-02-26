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
          Shift_L: toggle
          Shift_R: toggle
  '';

  # Wanxiang pinyin specific settings
  wanxiangCustomYaml = ''
    patch:
      __include: octagram   # 启用语法模型
      # Default to English (ASCII mode)
      switches/@0/reset: 1

      # Reliable Fuzzy Pinyin Rules (Directly mapped to avoid cross-file patch issues)
      "speller/algebra/__patch/0":
        __append:
          # an - ang
          - derive/([ui]?)([āáǎàa])ng(.*)$/$1$2n$3
          - derive/([ui]?)([āáǎàa])n(.*)$/$1$2ng$3
          # en - eng
          - derive/([ēéěèe])ng(.*)$/$1n$2
          - derive/([ēéěèe])n(.*)$/$1ng$2
          # in - ing
          - derive/([īíǐìi])ng(.*)$/$1n$2
          - derive/([īíǐìi])n(.*)$/$1ng$2
      
      # Symbol handling: stop '/' from calling candidate box
      speller/alphabet/=: "zyxwvutsrqponmlkjihgfedcbaZYXWVUTSRQPONMLKJIHGFEDCBA"
      speller/initials/=: "zyxwvutsrqponmlkjihgfedcbaZYXWVUTSRQPONMLKJIHGFEDCBA"
      "key_binder/shijian_keys/=": ["o"]
      "punctuator/half_shape/+/": "/"
      "punctuator/full_shape/+/": "/"

      # 语法模型配置
      octagram:
        __patch:
          grammar:
            language: wanxiang-lts-zh-hans
            collocation_max_length: 7
            collocation_min_length: 2
            collocation_penalty: -10
            non_collocation_penalty: -20
            weak_collocation_penalty: -35
            rear_penalty: -12
          translator/contextual_suggestions: false
          translator/max_homophones: 5
          translator/max_homographs: 5
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
    printf "%s" ${lib.escapeShellArg wanxiangCustomYaml} > $out/wanxiang.custom.yaml
  '';
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

  xdg.configFile."fcitx5/profile" = {
    text = ''
      [Groups/0]
      Name=Default
      Default Layout=us
      DefaultIM=rime

      # [Groups/0/Items/0]
      # Name=keyboard-us
      # Layout=

      # [Groups/0/Items/1]
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
