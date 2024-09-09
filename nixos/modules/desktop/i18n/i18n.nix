{
  pkgs,
  config,
  ...
}:
let
  rime-lantian-custom = pkgs.callPackage ./_rime-lantian-custom.nix { };
in
{
  i18n.inputMethod = {
    enabled = "ibus";
    ibus.engines = with pkgs.ibus-engines; [
      (
        (rime.override {
          librime = config.nur.repos.xddxdd.lantianCustomized.librime-with-plugins;
          rimeDataPkgs = with config.nur.repos.xddxdd; [
            pkgs.rime-data
            rime-dict
            rime-aurora-pinyin
            rime-ice
            rime-moegirl
            rime-zhwiki
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

              mkdir $out/data
              cp -rL $out/share/rime-data/* $out/data/
            '';
        })
      )
    ];
  };
  environment.global-persistence.user.directories = [
    ".config/ibus/rime"
    # ".config/fcitx5"
    # ".config/mozc"
  ];
}
