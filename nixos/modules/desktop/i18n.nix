{
  pkgs,
  config,
  ...
}: {
  i18n.inputMethod = {
    enabled = "fcitx5";
    fcitx5.addons = with pkgs; [
      (fcitx5-rime.override {
        rimeDataPkgs = with config.nur.repos.linyinfeng.rimePackages;
          withRimeDeps [
            rime-ice
          ];
      })
    ];
  };
  environment.global-persistence.user.directories = [
    # ".config/ibus"
    ".config/fcitx5"
    # ".config/mozc"
  ];
}
