{
  pkgs,
  lib,
  config,
  ...
}:
let
  rime-lantian-custom = pkgs.callPackage ./_rime-lantian-custom.nix { };

  fcitx5-rime-with-addons =
    (pkgs.fcitx5-rime.override {
      librime = pkgs.nur.repos.xddxdd.lantianCustomized.librime-with-plugins;
      rimeDataPkgs = with pkgs.nur.repos.xddxdd; [
        rime-aurora-pinyin
        rime-custom-pinyin-dictionary
        rime-dict
        rime-ice
        rime-moegirl
        rime-zhwiki
        pkgs.rime-data
        rime-lantian-custom
      ];
    }).overrideAttrs
      (old: {
        # Prebuild schema data
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.parallel ];
        postInstall =
          (old.postInstall or "")
          + ''
            for F in $out/share/rime-data/*.schema.yaml; do
              echo "rime_deployer --compile "$F" $out/share/rime-data $out/share/rime-data $out/share/rime-data/build" >> parallel.lst
            done
            parallel -j$(nproc) < parallel.lst || true
          '';
      });
in
{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      waylandFrontend = true;
      addons = with pkgs; [
        fcitx5-chinese-addons
        fcitx5-gtk
        fcitx5-rime-with-addons
        kdePackages.fcitx5-qt
      ];
    };
  };

  # Extra variables not covered by NixOS fcitx module
  environment.variables = lib.mkIf (!config.i18n.inputMethod.fcitx5.waylandFrontend) {
    INPUT_METHOD = "fcitx";
    SDL_IM_MODULE = "fcitx";
    GLFW_IM_MODULE = "ibus";
    QT_IM_MODULES = "wayland;fcitx;ibus";
  };
}
