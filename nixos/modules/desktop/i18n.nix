{
  pkgs,
  config,
  ...
}: {
  i18n = {
    defaultLocale = "en_US.UTF-8";
    inputMethod = {
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
  };
}
