{
  pkgs,
  config,
  ...
}: {
  i18n.inputMethod = {
    # enabled = "fcitx5";
    enabled = "ibus";
    # fcitx5.addons = with pkgs; [
    #   (fcitx5-rime.override {
    #     rimeDataPkgs = with config.nur.repos.linyinfeng.rimePackages;
    #       withRimeDeps [
    #         rime-ice
    #       ];
    #   })
    # ];
    ibus.engines = with pkgs.ibus-engines; [
      (rime.override {
        rimeDataPkgs = with config.nur.repos.linyinfeng.rimePackages; ((
            withRimeDeps [
              rime-ice
            ]
          )
          ++ (
            with config.nur.repos; [
              pkgs.rime-data
              linyinfeng.rimePackages.rime-emoji
              xddxdd.rime-moegirl
              xddxdd.rime-zhwiki
            ]
          ));
      })
    ];
  };
  environment.global-persistence.user.directories = [
    # ".config/ibus"
    ".config/fcitx5"
    # ".config/mozc"
  ];
}
