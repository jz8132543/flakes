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
  (final: prev: {
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

    # 移除破坏官方二进制缓存的 fcitx5-configtool 与 fcitx5-chinese-addons override，
    # 避免在每次 nixpkgs 更新时于本地从 C++ 源码重新编译这两个组件

    wpsoffice-cn = prev.symlinkJoin {
      name = "${prev.wpsoffice-cn.name or "wpsoffice-cn"}-no-scale";
      inherit (prev.wpsoffice-cn) version meta;
      paths = [ prev.wpsoffice-cn ];
      nativeBuildInputs = [ prev.makeWrapper ];
      postBuild = ''
        for bin in $out/bin/*; do
          if [ -f "$bin" ] && [ -x "$bin" ]; then
            wrapProgram "$bin" \
              --set QT_AUTO_SCREEN_SCALE_FACTOR 0 \
              --set QT_ENABLE_HIGHDPI_SCALING 0 \
              --set QT_SCALE_FACTOR 1
          fi
        done
      '';
    };

    perlPackages = prev.perlPackages.overrideScope (
      _pfinal: _pprev: {
        URIws = prev.emptyDirectory;
      }
    );

    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (_pyFinal: pyPrev: {
        pysaml2 = pyPrev.pysaml2.overridePythonAttrs (_: {
          doCheck = false;
        });
      })
    ];

    matrix-synapse-unwrapped = prev.matrix-synapse-unwrapped.overrideAttrs (_old: {
      doCheck = false;
      dontCheck = true;
      checkPhase = "";
      doInstallCheck = false;
      dontInstallCheck = true;
      installCheckPhase = "";
      nativeCheckInputs = [ ];
    });

    matrix-synapse = prev.matrix-synapse.override {
      inherit (final) matrix-synapse-unwrapped;
    };
  })
  (import "${self}/pkgs").overlay
]
