{
  inputs,
  self,
  ...
}:
[
  inputs.sops-nix.overlays.default
  inputs.rust-overlay.overlays.default
  inputs.chinese-fonts-overlay.overlays.default
  (
    _final: prev:
    {
    }
    // (self.lib.maybeAttrByPath "comma-with-db" inputs [
      "nix-index-database"
      "packages"
      prev.stdenv.hostPlatform.system
      "comma-with-db"
    ])
  )
  (_final: prev: {
    # qt6Packages = prev.qt6Packages.overrideScope (
    #   _qt6Final: qt6Prev: {
    #     libsForQt5 = (qt6Prev.libsForQt5 or (prev.libsForQt5.overrideScope (_: _: { }))).overrideScope (
    #       _qt5Final: _qt5Prev: {
    #         fcitx5-qt = null;
    #       }
    #     );
    #   }
    # );

    # inherit (final.qt6Packages) fcitx5-qt;

    fcitx5-configtool = prev.fcitx5-configtool.override { kcmSupport = false; };

    fcitx5-chinese-addons = prev.fcitx5-chinese-addons.override {
      enableCloudPinyin = false;
      enableOpencc = false;
      qtwebengine = null;
    };

    # python3Packages = prev.python3Packages.overrideScope (
    #   pyFinal: pyPrev: {
    #     kde-material-you-colors = pyPrev.kde-material-you-colors.overridePythonAttrs (old: {
    #       propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [ pyFinal.python-magic ];
    #     });
    #   }
    # );
  })
  (import "${self}/pkgs").overlay
]
