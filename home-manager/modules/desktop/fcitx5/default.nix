{
  pkgs,
  config,
  lib,
  ...
}:
{
  home.packages = with pkgs; [
    rime-wanxiang-base
    rime-wanxiang-gram
  ];

  home.file = {
    wanxiang_base = {
      source = "${pkgs.rime-wanxiang-base}/share/fcitx5/rime";
      target = ".local/share/fcitx5/rime";
      recursive = true;
    };

    wanxiang_gram = {
      source = "${pkgs.rime-wanxiang-gram}/share/fcitx5/rime/wanxiang-lts-zh-hans.gram";
      target = ".local/share/fcitx5/rime/wanxiang-lts-zh-hans.gram";
    };
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
    rm --recursive --force \
      "${config.xdg.configHome}/fcitx5/profile" \
      "${config.xdg.configHome}/fcitx5/config" \
      "${config.xdg.configHome}/fcitx5/conf"
  '';
}
